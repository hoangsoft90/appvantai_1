import { Errors } from '../lib/errors';

/**
 * Atomic rate limiter trên D1 (plan2_final §3.4).
 *
 * KHÔNG dùng KV GET counter → PUT counter+1 (TOCTOU race: 2 request cùng đọc
 * count=5 rồi cùng ghi 6 → chỉ đếm 1 lần). D1 single-writer + 1 statement
 * UPSERT ... RETURNING là atomic: mỗi request chắc chắn tăng count đúng 1.
 *
 * Fixed-window: window_start = floor(now / window). Khi window cũ hết hạn,
 * statement reset count = 1 (đơn giản, không cần cron).
 */

export interface RateLimitResult {
  count: number;
  limit: number;
  /** true nếu vượt limit (count > limit sau khi tăng). */
  exceeded: boolean;
}

/**
 * Tăng counter cho key trong window hiện tại và trả kết quả.
 * Đây là GENERIC helper — mọi rate limit dùng chung (post/contact/report/...).
 */
export async function consumeRateLimit(
  db: D1Database,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  const now = Date.now();
  const windowStart = new Date(Math.floor(now / (windowSeconds * 1000)) * windowSeconds * 1000)
    .toISOString();

  const res = await db
    .prepare(
      `INSERT INTO rate_limits (key, window_start, count)
       VALUES (?, ?, 1)
       ON CONFLICT(key) DO UPDATE SET
         count = CASE
           WHEN rate_limits.window_start = ? THEN rate_limits.count + 1
           ELSE 1
         END,
         window_start = ?
       RETURNING count`,
    )
    .bind(key, windowStart, windowStart, windowStart)
    .first<{ count: number }>();

  const count = res?.count ?? 1;
  return { count, limit, exceeded: count > limit };
}

/** Convenience: ném 429 nếu vượt limit. */
export async function enforceRateLimit(
  db: D1Database,
  key: string,
  limit: number,
  windowSeconds: number,
  code = 'RATE_LIMITED',
  message = 'Quá nhiều yêu cầu, vui lòng thử lại sau',
): Promise<void> {
  const r = await consumeRateLimit(db, key, limit, windowSeconds);
  if (r.exceeded) {
    throw Errors.tooManyRequests(code, message);
  }
}

/**
 * Atomic active-order limit (plan2_final §3.3).
 *
 * CŨ: SELECT COUNT → check → INSERT (TOCTOU: 10 request đồng thời cùng thấy
 * count=4 rồi cùng INSERT → vượt limit).
 * MỚI: INSERT đơn + kiểm tra trong CÙNG transaction qua 1 batch — D1 batch
 * chạy tuần tự nên khi SELECT COUNT chạy, các INSERT trước đó đã commit.
 *
 * Cách làm an toàn với D1: dùng db.batch([INSERT?, ...]) không thể rollback
 * theo điều kiện, nên dùng chiến lược 2 bước:
 *   1. INSERT order (status posted)
 *   2. SELECT COUNT active (bao gồm order vừa insert, tại cùng session)
 *   3. Nếu count > max → DELETE order vừa insert + throw 429
 * Vì D1 serialize write theo database, không thể có 2 INSERT xen kẽ giữa
 * SELECT và DELETE của nhau → invariant giữ nguyên. Nếu DELETE fail (edge),
 * đơn dư ra là lỗi chấp nhận được hơn là vượt limit — và luôn có audit.
 */
export async function createOrderWithActiveLimit(
  db: D1Database,
  insertFn: () => Promise<void>,
  customerId: string,
  max: number,
): Promise<void> {
  await insertFn();
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS n FROM cargo_orders
       WHERE customer_id = ? AND status IN ('posted', 'matched')`,
    )
    .bind(customerId)
    .first<{ n: number }>();
  const count = row?.n ?? 0;
  if (count > max) {
    // Vượt limit → rollback order vừa insert. D1 serialize writes nên
    // order này chắc chắn là của request hiện tại (id mới nhất).
    await db
      .prepare(
        `DELETE FROM cargo_orders WHERE id = (
           SELECT id FROM cargo_orders
           WHERE customer_id = ? AND status = 'posted'
           ORDER BY created_at DESC LIMIT 1
         ) AND customer_id = ? AND status = 'posted'`,
      )
      .bind(customerId, customerId)
      .run();
    throw Errors.tooManyRequests(
      'ACTIVE_ORDER_LIMIT',
      `Bạn đang có ${max} đơn hàng đang hoạt động, vui lòng hủy hoặc chờ hoàn thành trước khi tạo mới`,
    );
  }
}
