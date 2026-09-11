import type { Env } from '../env';
import { Errors } from '../lib/errors';
import { writeAuditLog } from './audit';
import { enforceRateLimit } from './rate_limit';
import { getUserById } from './users';

/**
 * Trust layer (plan §18): Report + Block.
 *  - Report: user tố cáo user khác (kèm order_id nếu có ngữ cảnh).
 *  - Block: user chặn user khác (không nhìn thấy nhau nữa).
 *  - Admin moderation: suspend/ban (xem admin routes).
 */

const REPORT_REASONS = ['spam', 'fake_info', 'harassment', 'fraud', 'other'];
const REPORT_RATE_MAX = 10;
const REPORT_RATE_WINDOW_SECONDS = 3600;

export interface ReportInput {
  target_user_id: string;
  order_id?: string;
  reason: string;
  description?: string;
}

export function validateReportInput(body: unknown): ReportInput {
  const b = (body ?? {}) as Record<string, unknown>;
  const target = String(b.target_user_id ?? '').trim();
  if (!target) {
    throw Errors.badRequest('INVALID_FIELD', 'Thiếu người bị báo cáo');
  }
  const reason = String(b.reason ?? '').trim();
  if (!REPORT_REASONS.includes(reason)) {
    throw Errors.badRequest('INVALID_REASON', `Lý do báo cáo không hợp lệ (cho phép: ${REPORT_REASONS.join(', ')})`);
  }
  return {
    target_user_id: target,
    order_id: b.order_id ? String(b.order_id).trim() : undefined,
    reason,
    description: String(b.description ?? '').trim().slice(0, 500),
  };
}

/**
 * Rate limit report: tối đa 10 lần/giờ mỗi reporter.
 * plan2_final §3.4: ATOMIC qua D1 (KV GET/PUT là TOCTOU race).
 */
export async function enforceReportRateLimit(db: D1Database, reporterId: string): Promise<void> {
  await enforceRateLimit(db, `reportrl:${reporterId}`, REPORT_RATE_MAX, REPORT_RATE_WINDOW_SECONDS,
    'REPORT_RATE_LIMITED', 'Bạn đã báo cáo quá nhiều trong thời gian ngắn, vui lòng thử lại sau');
}

export async function createReport(
  env: Env,
  reporterId: string,
  input: ReportInput,
  ip?: string,
): Promise<{ id: string; status: string }> {
  if (input.target_user_id === reporterId) {
    throw Errors.badRequest('INVALID_TARGET', 'Không thể báo cáo chính mình');
  }
  const target = await getUserById(env.DB, input.target_user_id);
  if (!target) {
    throw Errors.notFound('USER_NOT_FOUND', 'Người dùng không tồn tại');
  }
  // plan2_final §1.6: order_id phải tồn tại; reporter phải có quan hệ với order;
  // target phải là participant của order đó (nếu report gắn order).
  if (input.order_id) {
    const { getOrderById } = await import('./orders');
    const order = await getOrderById(env.DB, input.order_id);
    if (!order) {
      throw Errors.notFound('ORDER_NOT_FOUND', 'Đơn hàng không tồn tại');
    }
    const isParticipant = order.customer_id === reporterId || order.driver_id === reporterId;
    const hasContacted = order.customer_id !== reporterId
      ? await dbHasContactedOrder(env.DB, input.order_id, reporterId)
      : false;
    if (!isParticipant && !hasContacted) {
      throw Errors.forbidden('REPORT_NO_RELATION', 'Bạn không có quan hệ với đơn hàng này để báo cáo');
    }
    // plan2_final §1.6: target hợp lệ = participant (customer/driver được gán)
    // HOẶC driver đã liên hệ đơn (case phổ biến: chủ hàng report tài xế quấy rối sau contact).
    const targetIsRelated = order.customer_id === input.target_user_id
      || order.driver_id === input.target_user_id
      || (await dbHasContactedOrder(env.DB, input.order_id, input.target_user_id));
    if (!targetIsRelated) {
      throw Errors.badRequest('INVALID_TARGET', 'Người bị báo cáo không liên quan đến đơn hàng này');
    }
  }
  await enforceReportRateLimit(env.DB, reporterId);

  const id = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO reports (id, reporter_id, target_user_id, order_id, reason, description)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(id, reporterId, input.target_user_id, input.order_id ?? null, input.reason, input.description ?? '')
    .run();

  await writeAuditLog(env, {
    actorId: reporterId,
    entityType: 'report',
    entityId: id,
    action: 'report',
    metadata: { target_user_id: input.target_user_id, reason: input.reason },
    ip,
  });

  return { id, status: 'open' };
}

/** Helper nội bộ — tránh import cycle orders ↔ safety (dùng raw query). */
async function dbHasContactedOrder(db: D1Database, orderId: string, driverId: string): Promise<boolean> {
  const row = await db
    .prepare('SELECT 1 FROM contacts WHERE order_id = ? AND driver_id = ? LIMIT 1')
    .bind(orderId, driverId)
    .first();
  return row !== null;
}

export async function blockUser(
  env: Env,
  userId: string,
  blockedUserId: string,
  ip?: string,
): Promise<{ blocked: boolean }> {
  if (blockedUserId === userId) {
    throw Errors.badRequest('INVALID_TARGET', 'Không thể chặn chính mình');
  }
  const target = await getUserById(env.DB, blockedUserId);
  if (!target) {
    throw Errors.notFound('USER_NOT_FOUND', 'Người dùng không tồn tại');
  }
  await env.DB.prepare(
    `INSERT INTO blocks (id, user_id, blocked_user_id) VALUES (?, ?, ?)
     ON CONFLICT(user_id, blocked_user_id) DO NOTHING`,
  )
    .bind(crypto.randomUUID(), userId, blockedUserId)
    .run();

  await writeAuditLog(env, {
    actorId: userId,
    entityType: 'user',
    entityId: blockedUserId,
    action: 'block',
    ip,
  });

  return { blocked: true };
}

export async function unblockUser(
  env: Env,
  userId: string,
  blockedUserId: string,
): Promise<{ blocked: boolean }> {
  await env.DB.prepare('DELETE FROM blocks WHERE user_id = ? AND blocked_user_id = ?')
    .bind(userId, blockedUserId)
    .run();
  return { blocked: false };
}

/** Kiểm tra A đã block B chưa (dùng khi hiển thị contact/order). */
export async function isBlocked(db: D1Database, userId: string, otherUserId: string): Promise<boolean> {
  const row = await db
    .prepare('SELECT 1 FROM blocks WHERE user_id = ? AND blocked_user_id = ?')
    .bind(userId, otherUserId)
    .first();
  return row !== null;
}

/**
 * Hai bên đã block nhau theo bất kỳ chiều nào (plan2_final §1.5).
 * Dùng cho matching pre-filter (WHERE NOT EXISTS — 1 query) và
 * contact/accept (guard trước thao tác).
 */
export async function isBlockedEitherDirection(db: D1Database, a: string, b: string): Promise<boolean> {
  const row = await db
    .prepare(
      `SELECT 1 FROM blocks
       WHERE (user_id = ? AND blocked_user_id = ?) OR (user_id = ? AND blocked_user_id = ?)
       LIMIT 1`,
    )
    .bind(a, b, b, a)
    .first();
  return row !== null;
}