import type { Env } from '../env';
import { Errors } from '../lib/errors';
import { requireActiveDriverProfile, requireLegalConsent, requireNotBlockedEitherDirection } from './authorization';
import { writeAuditLog } from './audit';
import { getOrderById } from './orders';

/**
 * Atomic Accept (plan §10) — business invariant quan trọng nhất.
 *
 * 2 driver cùng accept một đơn → chỉ 1 người thành công.
 * KHÔNG dùng "SELECT rồi client tự accept" — dùng UPDATE có điều kiện:
 *   UPDATE ... SET driver_id = ? WHERE id = ? AND status IN ('posted','matched') AND driver_id IS NULL
 * rồi kiểm tra affected rows. D1 là single-writer nên UPDATE nguyên tử.
 */
export async function atomicAccept(
  env: Env,
  driverId: string,
  orderId: string,
  ip?: string,
): Promise<{ accepted: boolean; status: string }> {
  // plan2_final §1.1/§1.4/§1.5: driver active + consent + không block 2 chiều.
  const profile = await requireActiveDriverProfile(env.DB, driverId);

  // Check nhanh trước (cho lỗi rõ ràng, không tốn write)
  const order = await getOrderById(env.DB, orderId);
  if (!order) {
    throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
  }
  // Đã là driver của đơn → idempotent success (bấm accept lại không lỗi)
  if (order.driver_id === driverId) {
    return { accepted: true, status: 'accepted' };
  }
  // State machine (§9): POSTED/MATCHED/CONTACTED → ACCEPTED đều hợp lệ.
  // (Sau khi driver contact, đơn chuyển contacted — driver đó vẫn phải accept được.)
  if (order.status === 'cancelled' || order.status === 'expired' || order.status === 'rejected') {
    // plan2_final §2.2: không resurrect đơn terminal — 409 INVALID_TRANSITION (stable code).
    throw Errors.conflict(
      'INVALID_TRANSITION',
      `Đơn đã ở trạng thái cuối "${order.status}" — không thể nhận`,
    );
  }
  if (order.status !== 'posted' && order.status !== 'matched' && order.status !== 'contacted') {
    throw Errors.badRequest(
      'ORDER_ALREADY_ACCEPTED',
      `Đơn đã ở trạng thái "${order.status}" — không thể nhận`,
    );
  }

  // plan2_final §1.4/§1.5: consent + block (sau status-check nhanh, trước write).
  await requireLegalConsent(env.DB, driverId);
  if (order.customer_id) {
    await requireNotBlockedEitherDirection(env.DB, driverId, order.customer_id);
  }

  // Atomic UPDATE — D1 thực thi tuần tự, chỉ 1 driver thắng race.
  // Set luôn accepted_at (lifecycle timestamps — migration 0006, §13 correct timestamps).
  const res = await env.DB.prepare(
    `UPDATE cargo_orders
     SET driver_id = ?, status = 'accepted', accepted_at = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE id = ? AND status IN ('posted', 'matched', 'contacted') AND driver_id IS NULL`,
  )
    .bind(driverId, new Date().toISOString(), orderId)
    .run();

  if (res.meta.changes === 0) {
    // Ai đó đã accept trước (race) — trả 409 để client biết "đơn đã có người nhận"
    const latest = await getOrderById(env.DB, orderId);
    throw Errors.badRequest(
      'ORDER_ALREADY_ACCEPTED',
      latest && latest.driver_id === driverId
        ? 'Bạn đã nhận đơn này rồi'
        : 'Đơn đã được tài xế khác nhận',
    );
  }

  await writeAuditLog(env, {
    actorId: driverId,
    entityType: 'order',
    entityId: orderId,
    action: 'accept',
    ip,
  });

  return { accepted: true, status: 'accepted' };
}