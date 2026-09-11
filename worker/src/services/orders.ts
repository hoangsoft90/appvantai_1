import { Errors } from '../lib/errors';
import { createOrderWithActiveLimit } from './rate_limit';
import { VEHICLE_TYPES } from './profiles';

/**
 * Cargo orders (Phase 2 — Marketplace, plan §3.2, §11, §12).
 * - Grid Index: grid_lat/lng = FLOOR(pickup / 0.05) — Phase 3 dùng để
 *   cheap pre-filter (chỉ quét 9 ô lân cận).
 * - Lazy expiry (plan §19): đơn expires_at < now được coi là 'expired'
 *   khi query, không cần background job.
 * - Anti-spam (plan §19): rate limit tạo đơn (KV) + giới hạn đơn active.
 */

import { hasContactedOrder } from './contacts';

export const ORDER_STATUSES = [
  'posted', 'matched', 'contacted', 'accepted',
  'pickup', 'in_transit', 'delivered', 'completed',
  'cancelled', 'expired', 'rejected',
] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

export const CARGO_TYPES = [
  'general', 'food', 'fragile', 'furniture', 'electronics', 'building', 'other',
] as const;
export type CargoType = (typeof CARGO_TYPES)[number];

/** Trạng thái đơn còn "hoạt động" (chưa kết thúc/hủy). */
const ACTIVE_STATUSES: OrderStatus[] = ['posted', 'matched'];

export interface CargoOrder {
  id: string;
  customer_id: string;
  driver_id: string | null;
  pickup_lat: number;
  pickup_lng: number;
  pickup_address: string;
  delivery_lat: number;
  delivery_lng: number;
  delivery_address: string;
  cargo_type: string;
  weight_kg: number;
  length_cm: number;
  width_cm: number;
  height_cm: number;
  vehicle_requirement: string;
  pickup_from: string;
  pickup_to: string;
  price: number;
  notes: string;
  status: OrderStatus;
  grid_lat: number;
  grid_lng: number;
  expires_at: string;
  created_at: string;
  updated_at: string;
  accepted_at?: string | null;
  pickup_at?: string | null;
  in_transit_at?: string | null;
  delivered_at?: string | null;
  completed_at?: string | null;
  cancelled_at?: string | null;
}

/** Grid Index (plan §12): FLOOR(lat / 0.05). */
export function gridCell(value: number): number {
  return Math.floor(value / 0.05);
}

const ORDER_COLS = `
  id, customer_id, driver_id, pickup_lat, pickup_lng, pickup_address,
  delivery_lat, delivery_lng, delivery_address, cargo_type,
  weight_kg, length_cm, width_cm, height_cm, vehicle_requirement,
  pickup_from, pickup_to, price, notes, status,
  grid_lat, grid_lng, expires_at, created_at, updated_at,
  accepted_at, pickup_at, in_transit_at, delivered_at, completed_at, cancelled_at
`;

function now(): string {
  return new Date().toISOString();
}

function parseIso(value: unknown, field: string): string {
  const s = String(value ?? '');
  const d = Date.parse(s);
  if (Number.isNaN(d)) {
    throw Errors.badRequest('INVALID_DATETIME', `${field} không hợp lệ`);
  }
  return new Date(d).toISOString();
}

function intValue(v: unknown, max: number, label: string, required: boolean): number {
  if (v === undefined || v === null || v === '') {
    if (!required) return 0;
    throw Errors.badRequest('INVALID_FIELD', `Vui lòng nhập ${label.toLowerCase()}`);
  }
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0 || n > max || !Number.isInteger(n)) {
    throw Errors.badRequest('INVALID_FIELD', `${label} không hợp lệ`);
  }
  return n;
}

function coordValue(v: unknown, min: number, max: number, label: string): number {
  const n = Number(v);
  if (!Number.isFinite(n) || n < min || n > max) {
    throw Errors.badRequest('INVALID_COORD', `${label} không hợp lệ`);
  }
  return n;
}

function textValue(v: unknown, max: number, label: string, required: boolean): string {
  const s = String(v ?? '').trim();
  if (required && s.length === 0) {
    throw Errors.badRequest('INVALID_FIELD', `Vui lòng nhập ${label.toLowerCase()}`);
  }
  if (s.length > max) {
    throw Errors.badRequest('INVALID_FIELD', `${label} quá dài (tối đa ${max} ký tự)`);
  }
  return s;
}

export interface OrderInput {
  pickup_lat: number;
  pickup_lng: number;
  pickup_address: string;
  delivery_lat: number;
  delivery_lng: number;
  delivery_address: string;
  cargo_type: string;
  weight_kg: number;
  length_cm: number;
  width_cm: number;
  height_cm: number;
  vehicle_requirement: string;
  pickup_from: string;
  pickup_to: string;
  price: number;
  notes: string;
  expires_at: string;
}

/**
 * Validate + chuẩn hóa payload đơn hàng.
 * - create: mọi field bắt buộc, trả OrderInput đầy đủ.
 * - partial (PATCH): chỉ validate field được cung cấp, trả Partial<OrderInput>.
 */
export function validateOrderInput(body: unknown, opts: { partial?: boolean } = {}): Partial<OrderInput> {
  const b = (body ?? {}) as Record<string, unknown>;
  const out: Partial<OrderInput> = {};
  const partial = opts.partial ?? false;

  // present(field, required): create mode — required field vắng mặt → throw;
  // optional field vắng mặt → bỏ qua (default 0/'' được fill ở create-mode block).
  const present = (field: string, required: boolean): boolean => {
    if (b[field] !== undefined) return true;
    if (!partial && required) throw Errors.badRequest('INVALID_FIELD', `Thiếu trường ${field}`);
    return false;
  };

  const p = (field: string, required: boolean): boolean => present(field, required);

  if (p('pickup_lat', true)) out.pickup_lat = coordValue(b.pickup_lat, -90, 90, 'Vĩ độ điểm lấy');
  if (p('pickup_lng', true)) out.pickup_lng = coordValue(b.pickup_lng, -180, 180, 'Kinh độ điểm lấy');
  if (p('delivery_lat', true)) out.delivery_lat = coordValue(b.delivery_lat, -90, 90, 'Vĩ độ điểm giao');
  if (p('delivery_lng', true)) out.delivery_lng = coordValue(b.delivery_lng, -180, 180, 'Kinh độ điểm giao');
  if (p('pickup_address', false)) out.pickup_address = textValue(b.pickup_address, 300, 'Địa chỉ điểm lấy', false);
  if (p('delivery_address', false)) out.delivery_address = textValue(b.delivery_address, 300, 'Địa chỉ điểm giao', false);

  if (p('cargo_type', true)) {
    const t = String(b.cargo_type);
    if (!CARGO_TYPES.includes(t as CargoType)) {
      throw Errors.badRequest('INVALID_CARGO_TYPE', `Loại hàng không hợp lệ (cho phép: ${CARGO_TYPES.join(', ')})`);
    }
    out.cargo_type = t;
  }
  if (p('vehicle_requirement', true)) {
    const v = String(b.vehicle_requirement);
    if (v !== 'any' && !VEHICLE_TYPES.includes(v as (typeof VEHICLE_TYPES)[number])) {
      throw Errors.badRequest('INVALID_VEHICLE_REQUIREMENT', `Yêu cầu xe không hợp lệ (any hoặc ${VEHICLE_TYPES.join(', ')})`);
    }
    out.vehicle_requirement = v;
  }

  if (p('weight_kg', true)) out.weight_kg = intValue(b.weight_kg, 100_000, 'Khối lượng', true);
  if (p('length_cm', false)) out.length_cm = intValue(b.length_cm, 2_000, 'Chiều dài', false);
  if (p('width_cm', false)) out.width_cm = intValue(b.width_cm, 2_000, 'Chiều rộng', false);
  if (p('height_cm', false)) out.height_cm = intValue(b.height_cm, 2_000, 'Chiều cao', false);
  if (p('price', true)) out.price = intValue(b.price, 1_000_000_000, 'Giá', true);

  if (p('pickup_from', true)) out.pickup_from = parseIso(b.pickup_from, 'Thời gian lấy hàng');
  if (p('pickup_to', true)) out.pickup_to = parseIso(b.pickup_to, 'Thời gian lấy hàng (đến)');
  if (out.pickup_from !== undefined && out.pickup_to !== undefined && Date.parse(out.pickup_to) < Date.parse(out.pickup_from)) {
    throw Errors.badRequest('INVALID_TIME_RANGE', 'Thời gian lấy hàng "đến" phải sau "từ"');
  }
  if (p('notes', false)) out.notes = textValue(b.notes, 500, 'Ghi chú', false);
  if (p('expires_at', false)) {
    out.expires_at = parseIso(b.expires_at, 'Thời gian hết hạn');
    if (Date.parse(out.expires_at) < Date.now()) {
      throw Errors.badRequest('INVALID_EXPIRY', 'Thời gian hết hạn phải ở tương lai');
    }
  }

  // Tạo mới: bắt buộc đủ field + mặc định expires_at = pickup_to
  if (!partial) {
    const missing = ['pickup_lat', 'pickup_lng', 'delivery_lat', 'delivery_lng', 'cargo_type',
      'vehicle_requirement', 'weight_kg', 'price', 'pickup_from', 'pickup_to']
      .filter((f) => out[f as keyof OrderInput] === undefined);
    if (missing.length > 0) {
      throw Errors.badRequest('INVALID_FIELD', `Thiếu trường: ${missing.join(', ')}`);
    }
    // Default cho field không bắt buộc
    out.length_cm ??= 0;
    out.width_cm ??= 0;
    out.height_cm ??= 0;
    out.pickup_address ??= '';
    out.delivery_address ??= '';
    out.notes ??= '';
    if (out.expires_at === undefined) {
      out.expires_at = out.pickup_to as string;
    }
  }
  return out;
}

/** Rate limit tạo đơn: tối đa POST_RATE_MAX lần / POST_RATE_WINDOW giây (KV, plan §19). */
export async function enforcePostRateLimit(kv: KVNamespace, userId: string): Promise<void> {
  const KEY = 'postrl:';
  const MAX = 10;
  const WINDOW = 3600; // 1 giờ
  const count = Number((await kv.get(`${KEY}${userId}`)) ?? '0');
  if (count >= MAX) {
    throw Errors.tooManyRequests('POST_RATE_LIMITED', 'Bạn đã tạo quá nhiều đơn hàng trong thời gian ngắn, vui lòng thử lại sau');
  }
  await kv.put(`${KEY}${userId}`, String(count + 1), { expirationTtl: WINDOW });
}

/** Giới hạn đơn active (posted/matched) mỗi customer (plan §19). */
/**
 * Tạo đơn kèm active-order limit ATOMIC (plan2_final §3.3):
 * INSERT trước → COUNT trong cùng session (D1 serialize writes) → vượt limit
 * thì DELETE chính đơn vừa insert. Không còn cửa sổ TOCTOU giữa CHECK và INSERT.
 */
export async function createOrderChecked(
  db: D1Database,
  customerId: string,
  input: OrderInput,
  maxActive = 5,
): Promise<CargoOrder> {
  let createdId = '';
  await createOrderWithActiveLimit(
    db,
    async () => {
      const order = await insertOrder(db, customerId, input);
      createdId = order.id;
    },
    customerId,
    maxActive,
  );
  const order = await getOrderById(db, createdId);
  if (!order) throw Errors.internal('Không thể tạo đơn hàng');
  return order;
}

/**
 * ĐÃ THAY BỞI createOrderWithActiveLimit (rate_limit.ts) — plan2_final §3.3:
 * SELECT COUNT → INSERT là TOCTOU race, không dùng làm invariant duy nhất.
 * Giữ export này cho backward-compat kiểm tra mềm (không còn gọi ở route).
 */
export async function enforceActiveOrderLimit(db: D1Database, userId: string, max = 5): Promise<void> {
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS n FROM cargo_orders
       WHERE customer_id = ? AND status IN ('posted', 'matched')`,
    )
    .bind(userId)
    .first<{ n: number }>();
  if ((row?.n ?? 0) >= max) {
    throw Errors.tooManyRequests('ACTIVE_ORDER_LIMIT', `Bạn đang có ${max} đơn hàng đang hoạt động, vui lòng hủy hoặc chờ hoàn thành trước khi tạo mới`);
  }
}

/** Thuần INSERT (không check limit) — dùng bởi createOrderChecked. */
export async function insertOrder(db: D1Database, customerId: string, input: OrderInput): Promise<CargoOrder> {
  const id = crypto.randomUUID();
  await db
    .prepare(
      `INSERT INTO cargo_orders (
         id, customer_id, pickup_lat, pickup_lng, pickup_address,
         delivery_lat, delivery_lng, delivery_address, cargo_type,
         weight_kg, length_cm, width_cm, height_cm, vehicle_requirement,
         pickup_from, pickup_to, price, notes, status,
         grid_lat, grid_lng, expires_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'posted', ?, ?, ?)`,
    )
    .bind(
      id, customerId,
      input.pickup_lat, input.pickup_lng, input.pickup_address,
      input.delivery_lat, input.delivery_lng, input.delivery_address, input.cargo_type,
      input.weight_kg, input.length_cm, input.width_cm, input.height_cm, input.vehicle_requirement,
      input.pickup_from, input.pickup_to, input.price, input.notes,
      gridCell(input.pickup_lat), gridCell(input.pickup_lng), input.expires_at,
    )
    .run();
  const order = await getOrderById(db, id);
  if (!order) throw Errors.internal('Không thể tạo đơn hàng');
  return order;
}

export async function createOrder(db: D1Database, customerId: string, input: OrderInput): Promise<CargoOrder> {
  return insertOrder(db, customerId, input);
}

/** Lazy expiry (plan §19): đơn hết hạn được trả về với status='expired'. */
export function effectiveOrder(order: CargoOrder): CargoOrder {
  if (order.status === 'posted' && Date.parse(order.expires_at) < Date.now()) {
    return { ...order, status: 'expired' };
  }
  return order;
}

export async function getOrderById(db: D1Database, id: string): Promise<CargoOrder | null> {
  const row = await db
    .prepare(`SELECT ${ORDER_COLS} FROM cargo_orders WHERE id = ?`)
    .bind(id)
    .first<CargoOrder>();
  return row ? effectiveOrder(row) : null;
}

export async function listOrdersByCustomer(db: D1Database, customerId: string): Promise<CargoOrder[]> {
  const rows = await db
    .prepare(`SELECT ${ORDER_COLS} FROM cargo_orders WHERE customer_id = ? ORDER BY created_at DESC`)
    .bind(customerId)
    .all<CargoOrder>();
  return (rows.results ?? []).map(effectiveOrder);
}

export async function updateOrder(
  db: D1Database,
  orderId: string,
  customerId: string,
  input: Partial<OrderInput>,
): Promise<CargoOrder | null> {
  const existing = await getOrderById(db, orderId);
  if (!existing || existing.customer_id !== customerId) {
    throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
  }
  if (existing.status !== 'posted') {
    throw Errors.badRequest('INVALID_STATUS', 'Chỉ có thể chỉnh sửa đơn ở trạng thái "đang chờ"');
  }

  const sets: string[] = [];
  const binds: unknown[] = [];
  const put = (col: string, value: unknown) => {
    sets.push(`${col} = ?`);
    binds.push(value);
  };
  if (input.pickup_lat !== undefined) { put('pickup_lat', input.pickup_lat); put('grid_lat', gridCell(input.pickup_lat)); }
  if (input.pickup_lng !== undefined) { put('pickup_lng', input.pickup_lng); put('grid_lng', gridCell(input.pickup_lng)); }
  if (input.pickup_address !== undefined) put('pickup_address', input.pickup_address);
  if (input.delivery_lat !== undefined) put('delivery_lat', input.delivery_lat);
  if (input.delivery_lng !== undefined) put('delivery_lng', input.delivery_lng);
  if (input.delivery_address !== undefined) put('delivery_address', input.delivery_address);
  if (input.cargo_type !== undefined) put('cargo_type', input.cargo_type);
  if (input.weight_kg !== undefined) put('weight_kg', input.weight_kg);
  if (input.length_cm !== undefined) put('length_cm', input.length_cm);
  if (input.width_cm !== undefined) put('width_cm', input.width_cm);
  if (input.height_cm !== undefined) put('height_cm', input.height_cm);
  if (input.vehicle_requirement !== undefined) put('vehicle_requirement', input.vehicle_requirement);
  if (input.pickup_from !== undefined) put('pickup_from', input.pickup_from);
  if (input.pickup_to !== undefined) put('pickup_to', input.pickup_to);
  if (input.price !== undefined) put('price', input.price);
  if (input.notes !== undefined) put('notes', input.notes);
  if (input.expires_at !== undefined) put('expires_at', input.expires_at);

  if (sets.length === 0) {
    throw Errors.badRequest('INVALID_REQUEST', 'Không có trường nào để cập nhật');
  }
  sets.push("updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')");
  binds.push(orderId, customerId);
  await db
    .prepare(`UPDATE cargo_orders SET ${sets.join(', ')} WHERE id = ? AND customer_id = ?`)
    .bind(...binds)
    .run();
  const updated = await getOrderById(db, orderId);
  if (!updated) throw Errors.internal('Không thể cập nhật đơn hàng');
  return updated;
}

/**
 * plan2_final §1.2/§1.3 — quyền xem chi tiết đơn:
 *  - chủ đơn (customer)
 *  - driver được gán (driver_id)
 *  - driver đã liên hệ (contacts)
 *  - admin
 * Người khác (kể cả driver chưa liên hệ) → 404 (không leak tồn tại đơn).
 */
export async function assertOrderViewAccess(
  db: D1Database,
  order: CargoOrder,
  userId: string,
  role: string,
): Promise<void> {
  if (role === 'admin') return;
  if (order.customer_id === userId) return;
  if (order.driver_id === userId) return;
  if (await hasContactedOrder(db, order.id, userId)) return;
  throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
}

export async function cancelOrder(db: D1Database, orderId: string, customerId: string): Promise<CargoOrder | null> {
  const existing = await getOrderById(db, orderId);
  if (!existing || existing.customer_id !== customerId) {
    throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
  }
  if (!ACTIVE_STATUSES.includes(existing.status as OrderStatus)) {
    throw Errors.badRequest('INVALID_STATUS', 'Chỉ có thể hủy đơn ở trạng thái "đang chờ" hoặc "đã ghép"');
  }
  await db
    .prepare(
      `UPDATE cargo_orders SET status = 'cancelled', updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
       WHERE id = ? AND customer_id = ?`,
    )
    .bind(orderId, customerId)
    .run();
  return getOrderById(db, orderId);
}