import { Errors } from '../lib/errors';

/**
 * Centralized Order State Machine (plan2_final §2).
 *
 * MỘT contract duy nhất cho mọi transition — không route/service nào tự viết
 * điều kiện status rời rạc. Mọi endpoint đổi status ĐỀU đi qua đây.
 *
 * ```text
 * posted → matched → contacted → accepted → pickup → in_transit → delivered → completed
 * posted/matched/contacted → cancelled (customer — plan4_final §1: CHỈ cancel trước
 *                 khi driver accept; từ accepted trở đi xử lý qua report/lifecycle)
 * mọi trạng thái quá hạn mà chưa matched → expired (lazy, khi query)
 * ```
 */

export type OrderStatus =
  | 'posted' | 'matched' | 'contacted' | 'accepted'
  | 'pickup' | 'in_transit' | 'delivered' | 'completed'
  | 'cancelled' | 'expired' | 'rejected';

/** Trạng thái terminal — không thể transition đi đâu nữa (§2.2 không resurrect). */
const TERMINAL: readonly OrderStatus[] = ['completed', 'cancelled', 'expired', 'rejected'];

/**
 * Ma trận transition: from → allowed targets.
 * Actor authorization nằm ở từng API (customer/driver), ở đây chỉ validate
 * tính hợp lệ của mặt state.
 */
const TRANSITIONS: Record<OrderStatus, readonly OrderStatus[]> = {
  posted:      ['matched', 'contacted', 'accepted', 'cancelled', 'expired', 'rejected'],
  matched:     ['contacted', 'accepted', 'cancelled', 'expired', 'rejected'],
  contacted:   ['accepted', 'cancelled', 'expired', 'rejected'],
  accepted:    ['pickup'],
  pickup:      ['in_transit'],
  in_transit:  ['delivered'],
  delivered:   ['completed', 'cancelled'],
  completed:   [],
  cancelled:   [],
  expired:     [],
  rejected:    [],
};

export function isTerminal(status: string): boolean {
  return TERMINAL.includes(status as OrderStatus);
}

/**
 * Validate transition (§2.2). Ném 409 INVALID_TRANSITION nếu không hợp lệ —
 * error code ổn định cho client xử lý.
 */
export function canTransition(from: string, to: string): void {
  if (isTerminal(from)) {
    throw Errors.conflict('INVALID_TRANSITION', `Đơn đã ở trạng thái cuối "${from}", không thể chuyển sang "${to}"`);
  }
  const allowed = TRANSITIONS[from as OrderStatus];
  if (!allowed || !allowed.includes(to as OrderStatus)) {
    throw Errors.conflict('INVALID_TRANSITION', `Không thể chuyển đơn từ "${from}" sang "${to}"`);
  }
}

/**
 * Customer được hủy khi đơn còn ở 1 trong các trạng thái này (plan4_final §1).
 * Từ `accepted` trở đi tài xế đã nhận/lấy hàng → API phải từ chối với mã
 * ổn định CANCEL_NOT_ALLOWED để client xử lý (gợi ý liên hệ/báo cáo).
 */
export const CUSTOMER_CANCELLABLE: readonly OrderStatus[] = ['posted', 'matched', 'contacted'];

/** Danh sách transition hợp lệ từ 1 trạng thái (dùng cho test + debug). */
export function allowedFrom(from: string): readonly OrderStatus[] {
  return TRANSITIONS[from as OrderStatus] ?? [];
}

/** Timestamp cột tương ứng với trạng thái đích (migration 0006). */
export function statusTimestampColumn(to: OrderStatus): string | null {
  switch (to) {
    case 'accepted':   return 'accepted_at';
    case 'pickup':     return 'pickup_at';
    case 'in_transit': return 'in_transit_at';
    case 'delivered':  return 'delivered_at';
    case 'completed':  return 'completed_at';
    case 'cancelled':  return 'cancelled_at';
    default:           return null;
  }
}
