import type { Env } from '../env';
import { Errors } from '../lib/errors';
import { haversineKm } from '../lib/geo';
import type { LatLng } from '../lib/geo';
import { writeAuditLog } from './audit';
import { getOrderById } from './orders';
import { getTripById } from './trips';

/**
 * GPS (Phase 4 — plan §13).
 *
 * Chiến lược:
 *  - Chỉ GPS khi CÓ active trip (không track toàn bộ users).
 *  - Vị trí hiện tại lưu KV `loc:<driver_id>` (TTL ~2h), KHÔNG ghi D1
 *    realtime (D1 giới hạn 100k writes/ngày). Chỉ ghi D1 ở start/end trip.
 *  - Throttle: tối đa 1 location/30s (foreground), plan §13.
 *  - Privacy (§13, §18): KHÔNG public tọa độ chính xác — customer chỉ thấy
 *    "Tài xế cách ~2.3 km" (haversine từ điểm lấy, làm tròn 0.1 km).
 */

const LOC_TTL_SECONDS = 2 * 3600; // loc hết hạn sau 2h không update
const MIN_INTERVAL_MS = 30_000; // 30s giữa 2 lần update
const ACTIVE_STATUSES = ['planned', 'active'] as const;

export interface DriverLocation {
  lat: number;
  lng: number;
  updated_at: string;
}

/** Lấy vị trí hiện tại của driver từ KV (null nếu chưa có / hết hạn). */
export async function getDriverLocation(kv: KVNamespace, driverId: string): Promise<DriverLocation | null> {
  const raw = await kv.get(`loc:${driverId}`);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as DriverLocation;
  } catch {
    return null;
  }
}

/**
 * Driver gửi vị trí khi đang chạy chuyến (status planned/active).
 *  - Throttle 30s (KV lưu timestamp lần cuối) — chống spam write KV.
 *  - Không verify là trip thuộc driver ở đây (route đã làm); chỉ cần
 *    trip còn planned/active.
 */
export async function updateDriverLocation(
  kv: KVNamespace,
  driverId: string,
  lat: number,
  lng: number,
): Promise<{ updated_at: string; throttled: boolean }> {
  const lastKey = `loclast:${driverId}`;
  const last = Number((await kv.get(lastKey)) ?? '0');
  const now = Date.now();
  if (now - last < MIN_INTERVAL_MS) {
    return { updated_at: new Date(now).toISOString(), throttled: true };
  }
  await kv.put(lastKey, String(now), { expirationTtl: LOC_TTL_SECONDS });
  const payload: DriverLocation = { lat, lng, updated_at: new Date(now).toISOString() };
  await kv.put(`loc:${driverId}`, JSON.stringify(payload), { expirationTtl: LOC_TTL_SECONDS });
  return { updated_at: payload.updated_at, throttled: false };
}

/**
 * Khoảng cách ẩn danh từ điểm lấy hàng (privacy §13):
 * KHÔNG trả lat/lng — chỉ "cách ~X km" (làm tròn 0.1 km).
 * Chỉ chủ hàng của đơn đã được accept mới thấy (route check).
 */
export async function driverDistanceForOrder(
  env: Env,
  orderId: string,
  customerId: string,
): Promise<{ distance_km: number | null; updated_at: string | null }> {
  const order = await getOrderById(env.DB, orderId);
  if (!order || order.customer_id !== customerId) {
    throw Errors.notFound('ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng');
  }
  if (!order.driver_id) {
    throw Errors.badRequest('NO_DRIVER', 'Đơn chưa có tài xế nhận');
  }
  const loc = await getDriverLocation(env.APP_KV, order.driver_id);
  if (!loc) {
    return { distance_km: null, updated_at: null };
  }
  const pickup: LatLng = { lat: order.pickup_lat, lng: order.pickup_lng };
  const km = haversineKm(pickup, { lat: loc.lat, lng: loc.lng });
  return { distance_km: Math.round(km * 10) / 10, updated_at: loc.updated_at };
}

/** Bắt đầu chuyến: planned → active (ghi started_at — 1 D1 write duy nhất). */
export async function startTrip(
  env: Env,
  tripId: string,
  driverId: string,
  ip?: string,
): Promise<{ status: string; started_at: string }> {
  const trip = await getTripById(env.DB, driverId, tripId);
  if (!trip) throw Errors.notFound('TRIP_NOT_FOUND', 'Không tìm thấy chuyến');
  if (trip.status === 'ended' || trip.status === 'cancelled') {
    throw Errors.badRequest('TRIP_NOT_ACTIVE', 'Chuyến đã kết thúc hoặc bị hủy');
  }
  if (trip.status === 'active') {
    return { status: trip.status, started_at: trip.started_at ?? new Date().toISOString() };
  }
  const startedAt = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE trips SET status = 'active', started_at = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE id = ? AND driver_id = ?`,
  )
    .bind(startedAt, tripId, driverId)
    .run();
  await writeAuditLog(env, { actorId: driverId, entityType: 'trip', entityId: tripId, action: 'trip_start', ip });
  return { status: 'active', started_at: startedAt };
}

/** Kết thúc chuyến: active → ended + xóa loc KV (ngừng track). */
export async function endTrip(
  env: Env,
  tripId: string,
  driverId: string,
  ip?: string,
): Promise<{ status: string; ended_at: string }> {
  const trip = await getTripById(env.DB, driverId, tripId);
  if (!trip) throw Errors.notFound('TRIP_NOT_FOUND', 'Không tìm thấy chuyến');
  if (trip.status === 'ended' || trip.status === 'cancelled') {
    throw Errors.badRequest('TRIP_NOT_ACTIVE', 'Chuyến đã kết thúc hoặc bị hủy');
  }
  const endedAt = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE trips SET status = 'ended', ended_at = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE id = ? AND driver_id = ?`,
  )
    .bind(endedAt, tripId, driverId)
    .run();
  // Ngừng track: xóa loc + last
  await env.APP_KV.delete(`loc:${driverId}`);
  await env.APP_KV.delete(`loclast:${driverId}`);
  await writeAuditLog(env, { actorId: driverId, entityType: 'trip', entityId: tripId, action: 'trip_end', ip });
  return { status: 'ended', ended_at: endedAt };
}

export { ACTIVE_STATUSES };