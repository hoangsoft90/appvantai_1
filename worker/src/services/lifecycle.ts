import type { Env } from '../env';
import { Errors } from '../lib/errors';
import { writeAuditLog } from './audit';
import { requireLegalConsent } from './authorization';
import { canTransition, CUSTOMER_CANCELLABLE, type OrderStatus } from './order_state_machine';
import { getOrderById, type CargoOrder } from './orders';

/**
 * Order Lifecycle APIs (plan2_final §2.3, §2.4).
 *
 * Actor rules (§2.4):
 *  - Customer: create / view own / cancel theo rule / complete sau delivered.
 *  - Driver:   accept / pickup / in_transit / delivered (driver cancel: P1).
 *  - Admin:    moderation có audit log (routes/admin.ts).
 *
 * Mọi transition ĐỀU qua canTransition() (§2.2) + UPDATE có điều kiện
 * (status hiện tại nằm trong WHERE) để concurrent request không ghi đè nhau (§3).
 */

interface TransitionRule {
  actor: 'customer' | 'driver';
  target: OrderStatus;
  from: readonly OrderStatus[];
  /** Điều kiện bổ sung trong WHERE (text). */
  whereExtra?: string;
  /** Bind actorId vào whereExtra (vd: AND driver_id = ?). */
  whereBindActor?: boolean;
  /** SET driver_id = actorId (dùng cho accept). */
  setDriverId?: boolean;
  /** Driver phải là driver được gán của đơn (pickup/in_transit/delivered). */
  requireAssigned?: boolean;
  tsColumn: string | null;
}

/** Contract actor→transition (§2.4). Mỗi API lifecycle ánh xạ đúng 1 rule. */
const RULES: Record<string, TransitionRule> = {
  accept: {
    actor: 'driver',
    target: 'accepted',
    from: ['posted', 'matched', 'contacted'],
    whereExtra: 'AND driver_id IS NULL',
    setDriverId: true,
    tsColumn: 'accepted_at',
  },
  pickup: {
    actor: 'driver',
    target: 'pickup',
    from: ['accepted'],
    whereExtra: 'AND driver_id = ?',
    whereBindActor: true,
    requireAssigned: true,
    tsColumn: 'pickup_at',
  },
  in_transit: {
    actor: 'driver',
    target: 'in_transit',
    from: ['pickup'],
    whereExtra: 'AND driver_id = ?',
    whereBindActor: true,
    requireAssigned: true,
    tsColumn: 'in_transit_at',
  },
  delivered: {
    actor: 'driver',
    target: 'delivered',
    from: ['in_transit'],
    whereExtra: 'AND driver_id = ?',
    whereBindActor: true,
    requireAssigned: true,
    tsColumn: 'delivered_at',
  },
  complete: {
    actor: 'customer',
    target: 'completed',
    from: ['delivered'],
    whereExtra: 'AND customer_id = ?',
    whereBindActor: true,
    tsColumn: 'completed_at',
  },
  cancel: {
    // plan4_final §1: customer CHỈ hủy được khi posted/matched/contacted —
    // từ accepted trở đi tài xế đã nhận/lấy hàng → CANCEL_NOT_ALLOWED.
    // Ghi chú plan cũ "cancel trước khi in_transit" không còn đúng.
    actor: 'customer',
    target: 'cancelled',
    from: CUSTOMER_CANCELLABLE,
    whereExtra: 'AND customer_id = ?',
    whereBindActor: true,
    tsColumn: 'cancelled_at',
  },
};

const ACTION_NAMES = Object.keys(RULES) as (keyof typeof RULES & string)[];
export type LifecycleAction = (typeof ACTION_NAMES)[number];

export interface TransitionOutcome {
  order: CargoOrder;
  status: OrderStatus;
  from: string;
}

/**
 * Thực hiện 1 transition có kiểm soát.
 *  - Ném 404 nếu không thấy đơn / không thuộc actor; 409 nếu transition sai hoặc race.
 */
export async function transitionOrder(
  env: Env,
  action: LifecycleAction,
  orderId: string,
  actorId: string,
  ip?: string,
): Promise<TransitionOutcome> {
  const rule = RULES[action];
  if (!rule) throw Errors.internal(`Unknown lifecycle action: ${action}`);

  const order = await getOrderById(env.DB, orderId);
  if (!order) {
    throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
  }

  // Ownership/actor check (§1.2) — 404 cho người ngoài (không leak existence).
  if (rule.actor === 'customer' && order.customer_id !== actorId) {
    throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
  }
  if (rule.actor === 'driver') {
    // pickup/in_transit/delivered: CHỈ driver được gán (driver_id null → 404,
    // vì driver chưa accept không có quyền thấy thao tác lifecycle).
    if (rule.requireAssigned && order.driver_id !== actorId) {
      throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
    }
    // accept: driver_id null là bình thường (chưa ai nhận).
    if (!rule.requireAssigned && order.driver_id !== null && order.driver_id !== actorId) {
      throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
    }
    if (order.customer_id === actorId) {
      throw Errors.forbidden('ROLE_FORBIDDEN', 'Chỉ tài xế mới thực hiện được thao tác này');
    }
  }

  // Consent (§1.4) — mọi lifecycle action cần consent đã tick.
  await requireLegalConsent(env.DB, actorId);

  // plan4_final §1: cancel sau accepted → mã ổn định riêng cho client
  // (CANCEL_NOT_ALLOWED, 409) — check TRƯỚC canTransition để không bị nuốt
  // vào INVALID_TRANSITION chung.
  if (action === 'cancel' && !CUSTOMER_CANCELLABLE.includes(order.status as OrderStatus)) {
    throw Errors.conflict(
      'CANCEL_NOT_ALLOWED',
      'Không thể hủy đơn sau khi tài xế đã nhận. Hãy liên hệ hoặc báo cáo sự cố.',
    );
  }

  // State machine validate (§2.2) — ném 409 INVALID_TRANSITION nếu sai.
  canTransition(order.status, rule.target);

  // Xây UPDATE có điều kiện. Thứ tự bind: [SET values] + [WHERE values].
  const setFragments: string[] = ['status = ?'];
  const setBinds: unknown[] = [rule.target];
  if (rule.setDriverId) {
    setFragments.push('driver_id = ?');
    setBinds.push(actorId);
  }
  if (rule.tsColumn) {
    setFragments.push(`${rule.tsColumn} = ?`);
    setBinds.push(new Date().toISOString());
  }
  setFragments.push("updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')");

  const fromList = rule.from.map(() => '?').join(',');
  const whereFragment = `id = ? AND status IN (${fromList})${rule.whereExtra ?? ''}`;
  const whereBinds: unknown[] = [orderId, ...rule.from];
  if (rule.whereBindActor) whereBinds.push(actorId);

  const res = await env.DB
    .prepare(`UPDATE cargo_orders SET ${setFragments.join(', ')} WHERE ${whereFragment}`)
    .bind(...setBinds, ...whereBinds)
    .run();

  if (res.meta.changes === 0) {
    // Race: ai đó đã đổi status trước — re-read + 409 rõ ràng (§2.2 stable code).
    const latest = await getOrderById(env.DB, orderId);
    throw Errors.conflict(
      'INVALID_TRANSITION',
      `Đơn đang ở trạng thái "${latest?.status ?? 'không rõ'}" — không thể thực hiện "${action}"`,
    );
  }

  await writeAuditLog(env, {
    actorId,
    entityType: 'order',
    entityId: orderId,
    action: `order_${action}`,
    metadata: { from: order.status, to: rule.target },
    ip,
  });

  const updated = await getOrderById(env.DB, orderId);
  if (!updated) throw Errors.internal('Không thể đọc đơn sau khi cập nhật');
  return { order: updated, status: updated.status, from: order.status };
}
