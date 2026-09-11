import type { Env } from '../env';
import { Errors } from '../lib/errors';
import { writeAuditLog } from './audit';
import { requireActiveDriverProfile, requireLegalConsent, requireNotBlockedEitherDirection } from './authorization';
import { enforceRateLimit } from './rate_limit';
import { getOrderById } from './orders';
import { getUserById } from './users';

/** Driver đã liên hệ đơn này chưa (plan2_final §1.2 — quyền xem đơn). */
export async function hasContactedOrder(db: D1Database, orderId: string, driverId: string): Promise<boolean> {
  const row = await db
    .prepare('SELECT 1 FROM contacts WHERE order_id = ? AND driver_id = ? LIMIT 1')
    .bind(orderId, driverId)
    .first();
  return row !== null;
}

/**
 * Contact (plan §17, §19): driver bấm "Liên hệ chủ hàng" → ghi CONTACTED.
 * P0: không realtime chat — liên hệ qua điện thoại (app hiển thị số).
 * Rate limit theo driver để chống spam contact (§19).
 */

const CONTACT_RATE_MAX = 20;
const CONTACT_RATE_WINDOW_SECONDS = 3600;

export interface ContactResult {
  order_id: string;
  status: string;
  /** Số điện thoại của bên kia — chỉ hiện sau khi contact (privacy §18). */
  phone: string;
  name: string;
  contact_type: 'phone';
  created_at: string;
}

/**
 * Rate limit contact: tối đa 20 lần/giờ mỗi driver.
 * plan2_final §3.4: ATOMIC qua D1 (KV GET/PUT là TOCTOU race).
 */
export async function enforceContactRateLimit(db: D1Database, driverId: string): Promise<void> {
  await enforceRateLimit(db, `contactrl:${driverId}`, CONTACT_RATE_MAX, CONTACT_RATE_WINDOW_SECONDS,
    'CONTACT_RATE_LIMITED', 'Bạn đã liên hệ quá nhiều trong thời gian ngắn, vui lòng thử lại sau');
}

/**
 * Driver contact chủ hàng của một đơn posted/matched.
 *  - plan2_final §1.3: role/eligibility/status được check TRƯỚC khi cấp phone;
 *    phone chỉ trả khi operation thành công.
 *  - plan2_final §1.4: legal consent enforce server-side.
 *  - plan2_final §1.5: block 2 chiều chặn contact.
 *  - Ghi contacts + chuyển đơn → contacted (chỉ khi đang posted/matched),
 *    re-check status trong UPDATE để concurrent contact không resurrect đơn.
 */
export async function contactDriverToCustomer(
  env: Env,
  driverId: string,
  orderId: string,
  ip?: string,
): Promise<ContactResult> {
  const order = await getOrderById(env.DB, orderId);
  if (!order || order.status === 'expired') {
    throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
  }
  if (order.status !== 'posted' && order.status !== 'matched') {
    throw Errors.badRequest('INVALID_STATUS', 'Đơn hàng không còn nhận liên hệ');
  }

  // plan2_final §1.3/§1.4/§1.5: driver active + consent + không block 2 chiều.
  await requireActiveDriverProfile(env.DB, driverId);
  await requireLegalConsent(env.DB, driverId);
  await requireNotBlockedEitherDirection(env.DB, driverId, order.customer_id);

  await enforceContactRateLimit(env.DB, driverId);

  const customer = await getUserById(env.DB, order.customer_id);
  if (!customer || customer.status !== 'active') {
    throw Errors.badRequest('USER_UNAVAILABLE', 'Chủ hàng không khả dụng');
  }

  const id = crypto.randomUUID();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO contacts (id, order_id, driver_id, customer_id, contact_type)
       VALUES (?, ?, ?, ?, 'phone')`,
    ).bind(id, orderId, driverId, order.customer_id),
    // Contacted (chỉ nếu còn posted/matched — driver khác contact sau accept thì fail vô hại)
    env.DB.prepare(
      `UPDATE cargo_orders SET status = 'contacted', updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
       WHERE id = ? AND status IN ('posted', 'matched')`,
    ).bind(orderId),
  ]);

  await writeAuditLog(env, {
    actorId: driverId,
    entityType: 'order',
    entityId: orderId,
    action: 'contact',
    metadata: { contact_id: id },
    ip,
  });

  return {
    order_id: orderId,
    status: 'contacted',
    phone: customer.phone,
    name: customer.name,
    contact_type: 'phone',
    created_at: new Date().toISOString(),
  };
}