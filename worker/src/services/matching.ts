import type { Env } from '../env';
import type { MapsProvider } from '../maps/provider';
import {
  bearingDeg,
  bearingDiffDeg,
  decodePolyline,
  distanceToPolylineKm,
  haversineKm,
  resamplePolyline,
} from '../lib/geo';
import type { LatLng } from '../lib/geo';
import { gridCell, type CargoOrder } from './orders';
import { getDriverProfile } from './profiles';
import { getCachedRoute } from './route_cache';
import type { Trip } from './trips';

/**
 * Route-aware Matching Engine (plan §5.1-5.3) — CORE VALUE của app.
 *
 * Pipeline:
 *  1. Cheap pre-filter (D1, Grid Index §12): status/expiry/vehicle/capacity + corridor cells
 *  2. Route corridor: pickup → nearest route point (Haversine + point-to-line)
 *  3. Direction: bearing driver A→B vs cargo pickup→delivery
 *  4. Vehicle compatibility (hard reject)
 *  5. Time (hard reject nếu hết khung giờ)
 *  6. Expensive verification (chỉ Top N): detour OSRM (cached), >15km hard reject
 *
 * Score: 110 subtotal + 15 detour bonus = 125 → normalize về 100 (plan §6).
 */

const MAX_PICKUP_DISTANCE_KM = 10; // pickup quá xa tuyến → hard reject
const MAX_DETOUR_KM = 15; // plan §5.3: >15km hard reject
const TOP_N = 5; // chỉ Top N mới gọi routing (plan §5.3, §14)
const OPPOSITE_ANGLE = 135; // ngược hướng nghiêm trọng → hard reject

export interface MatchResult {
  score: number;
  subtotal: number;
  detour_km: number | null;
  /** Khoảng cách điểm lấy hàng khỏi tuyến (km) — plan3 Mục 4: hiện trên match card. */
  pickup_km: number;
  reasons: string[];
  order: CargoOrder;
  components: {
    distance: number;
    route: number;
    direction: number;
    vehicle: number;
    capacity: number;
    time: number;
  };
}

interface Scored {
  order: CargoOrder;
  subtotal: number;
  pickup_km: number;
  angle_deg: number;
  components: { distance: number; route: number; direction: number; vehicle: number; capacity: number; time: number };
}

export async function runMatching(env: Env, maps: MapsProvider, trip: Trip): Promise<MatchResult[]> {
  const profile = await getDriverProfile(env.DB, trip.driver_id);
  if (!profile || profile.status !== 'active') return [];
  const capacity = profile.capacity_kg;
  const vehicleType = profile.vehicle_type;

  const corridor = resamplePolyline(decodePolyline(trip.route_polyline), 300);
  const origin: LatLng = { lat: trip.origin_lat, lng: trip.origin_lng };
  const destination: LatLng = { lat: trip.destination_lat, lng: trip.destination_lng };

  // plan2_final §4.1 — Return Trip:
  //  - one_way: driver chạy A→B, nhận hàng cùng chiều (pickup → delivery ≈ A→B).
  //  - return:  driver chạy A→B XE RỖNG, tìm hàng B→A (chiều về).
  //    → bearing driver = B→A, corridor là TUYẾN ĐI nhưng tính điểm theo chiều ngược.
  const isReturn = trip.trip_type === 'return';
  const driverBearing = isReturn
    ? bearingDeg(destination, origin)        // chiều về: B→A
    : bearingDeg(origin, destination);       // chiều đi: A→B

  // ---- Step 1: cheap pre-filter (Grid Index, plan §12 + block §1.5 plan2_final) ----
  const orders = await corridorFilter(env, corridor, vehicleType, capacity, trip.driver_id);

  // ---- Steps 2-5: corridor / direction / vehicle / capacity / time ----
  const now = Date.now();
  const scored: Scored[] = [];

  for (const order of orders) {
    const pickup: LatLng = { lat: order.pickup_lat, lng: order.pickup_lng };
    const delivery: LatLng = { lat: order.delivery_lat, lng: order.delivery_lng };

    const pickupKm = distanceToPolylineKm(pickup, corridor);
    if (pickupKm > MAX_PICKUP_DISTANCE_KM) continue; // hard reject: pickup quá xa tuyến

    // plan2_final §4.1: bearing cargo LUÔN theo chiều cargo (pickup→delivery);
    // bearing driver đổi theo trip_type. So khớp 2 bearing.
    const angle = bearingDiffDeg(driverBearing, bearingDeg(pickup, delivery));
    if (angle > OPPOSITE_ANGLE) continue; // hard reject: ngược hướng nghiêm trọng

    if (Date.parse(order.pickup_to) < now) continue; // hard reject: hết khung giờ lấy

    // plan2_final §4.2 — Pickup feasibility:
    // một chiều = điểm xuất phát hiệu lực của driver → pickup.
    // return: driver xuất phát từ B (destination của tuyến); one_way: từ A (origin).
    const effectiveOrigin = isReturn ? destination : origin;
    const pickupTravelKm = haversineKm(effectiveOrigin, pickup);
    // Tốc độ kế hoạch bảo thủ 40 km/h đường bộ VN + buffer 30 phút.
    // Hard reject nếu KHÔNG THỂ tới pickup trước cửa sổ đóng.
    const travelMinutes = (pickupTravelKm / 40) * 60 + 30;
    const minutesUntilClose = (Date.parse(order.pickup_to) - now) / 60_000;
    if (minutesUntilClose < travelMinutes) continue; // chắc chắn không kịp lấy hàng

    const components = {
      distance: originDistanceScore(pickupTravelKm),
      route: routeScoreFromKm(pickupKm),
      direction: directionScoreFromAngle(angle),
      vehicle: 15, // sót lại sau filter = xe đã tương thích
      capacity: capacityScore(order.weight_kg, capacity),
      time: timeScore(order.pickup_from, now),
    };
    const subtotal = components.distance + components.route + components.direction +
      components.vehicle + components.capacity + components.time;

    scored.push({ order, subtotal, pickup_km: pickupKm, angle_deg: angle, components });
  }

  // ---- Step 6: Top-N detour verification (OSRM cached) ----
  scored.sort((a, b) => b.subtotal - a.subtotal);
  const topN = scored.slice(0, TOP_N);
  const baseKm = trip.distance_m / 1000;

  const results: MatchResult[] = [];
  for (const c of topN) {
    const pickup: LatLng = { lat: c.order.pickup_lat, lng: c.order.pickup_lng };
    const delivery: LatLng = { lat: c.order.delivery_lat, lng: c.order.delivery_lng };
    // plan2_final §4.1: detour theo chiều phù hợp.
    //  - one_way: origin→pickup→delivery→destination (hàng gắn vào tuyến đi).
    //  - return:  destination→pickup→delivery→origin (hàng chiều về, driver từ B).
    const routeStart = isReturn ? destination : origin;
    const routeEnd = isReturn ? origin : destination;
    let detourKm: number | null = null;
    try {
      const r1 = await getCachedRoute(env.DB, maps, routeStart, pickup);
      const r2 = await getCachedRoute(env.DB, maps, pickup, delivery);
      const r3 = await getCachedRoute(env.DB, maps, delivery, routeEnd);
      detourKm = (r1.distance_m + r2.distance_m + r3.distance_m) / 1000 - baseKm;
    } catch {
      detourKm = null; // routing lỗi → bỏ qua detour, vẫn giữ subtotal
    }
    if (detourKm !== null && detourKm > MAX_DETOUR_KM) continue; // hard reject: detour quá lớn

    const bonus = detourKm === null ? 0 : detourKm < 3 ? 15 : detourKm <= 7 ? 10 : 5;
    const total = c.subtotal + bonus;
    const score = Math.round((total / 125) * 100);

    results.push({
      score,
      subtotal: c.subtotal,
      detour_km: detourKm,
      pickup_km: c.pickup_km,
      reasons: buildReasons(c, detourKm),
      order: c.order,
      components: c.components,
    });
  }

  results.sort((a, b) => b.score - a.score);
  await persistMatches(env.DB, trip.id, results);
  return results;
}

/**
 * Pre-filter theo corridor grid range (index-backed, plan §12).
 * plan2_final §1.5: block được enforce ở matching — đơn của user đã block
 * driver (2 chiều) bị loại ngay ở SQL, không tốn scoring.
 */
async function corridorFilter(
  env: Env,
  corridor: LatLng[],
  vehicleType: string,
  capacity: number,
  driverId: string,
): Promise<CargoOrder[]> {
  let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
  for (const p of corridor) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lng < minLng) minLng = p.lng;
    if (p.lng > maxLng) maxLng = p.lng;
  }
  const gx1 = Math.floor(minLat / 0.05) - 1;
  const gx2 = Math.floor(maxLat / 0.05) + 1;
  const gy1 = Math.floor(minLng / 0.05) - 1;
  const gy2 = Math.floor(maxLng / 0.05) + 1;

  const rows = await env.DB
    .prepare(
      `SELECT id, customer_id, pickup_lat, pickup_lng, pickup_address,
              delivery_lat, delivery_lng, delivery_address, cargo_type,
              weight_kg, length_cm, width_cm, height_cm, vehicle_requirement,
              pickup_from, pickup_to, price, notes, status,
              grid_lat, grid_lng, expires_at, created_at, updated_at
       FROM cargo_orders
       WHERE status = 'posted'
         AND expires_at > ?
         AND (vehicle_requirement = 'any' OR vehicle_requirement = ?)
         AND weight_kg <= ?
         AND grid_lat BETWEEN ? AND ?
         AND grid_lng BETWEEN ? AND ?
         AND NOT EXISTS (
           SELECT 1 FROM blocks
           WHERE (blocks.user_id = cargo_orders.customer_id AND blocks.blocked_user_id = ?)
              OR (blocks.user_id = ? AND blocks.blocked_user_id = cargo_orders.customer_id)
         )`,
    )
    .bind(new Date().toISOString(), vehicleType, capacity, gx1, gx2, gy1, gy2, driverId, driverId)
    .all<CargoOrder>();
  return rows.results ?? [];
}

// ---- Scoring (plan §6) ----

function routeScoreFromKm(km: number): number {
  if (km <= 1) return 30;
  if (km <= 2) return 25;
  if (km <= 3) return 20;
  if (km <= 5) return 12;
  return 5;
}

function originDistanceScore(km: number): number {
  if (km <= 10) return 20;
  if (km <= 25) return 14;
  if (km <= 50) return 8;
  if (km <= 80) return 3;
  return 0;
}

function directionScoreFromAngle(deg: number): number {
  if (deg <= 45) return 25;
  if (deg <= 90) return 15;
  return 5;
}

function capacityScore(weight: number, capacity: number): number {
  if (capacity <= 0) return 0;
  const ratio = weight / capacity;
  if (ratio <= 0.6) return 10;
  if (ratio <= 0.8) return 8;
  return 5;
}

function timeScore(pickupFromIso: string, now: number): number {
  const hours = (Date.parse(pickupFromIso) - now) / 3_600_000;
  if (hours <= 24) return 10;
  if (hours <= 48) return 6;
  if (hours <= 72) return 3;
  return 1;
}

// ---- Match reasons (plan §7: không trả con số "91" mà không giải thích) ----

function buildReasons(c: Scored, detourKm: number | null): string[] {
  const reasons: string[] = [];
  reasons.push(`Điểm lấy cách tuyến ${c.pickup_km.toFixed(1)} km`);
  if (c.angle_deg <= 45) reasons.push('Điểm giao cùng hướng tuyến');
  else if (c.angle_deg <= 90) reasons.push('Điểm giao gần cùng hướng');
  else reasons.push('Điểm giao lệch hướng nhẹ');
  reasons.push(
    c.order.vehicle_requirement === 'any'
      ? 'Không yêu cầu loại xe'
      : `Phù hợp yêu cầu xe ${c.order.vehicle_requirement}`,
  );
  reasons.push(`Đủ tải trọng (${c.order.weight_kg} kg)`);
  reasons.push('Thời gian lấy hàng phù hợp');
  if (detourKm !== null) reasons.push(`Độ lệch tuyến chỉ ${detourKm.toFixed(1)} km`);
  return reasons;
}

/**
 * Lưu matches cho funnel metrics (plan §29) — thay toàn bộ kết quả cũ của trip.
 * plan2_final §3.5: db.batch là ATOMIC (transaction) — không còn nguy cơ
 * DELETE xong rồi INSERT lỗi giữa chừng làm mất snapshot cũ + snapshot mới partial.
 * Batch rỗng (0 results) vẫn thực hiện DELETE để clear snapshot cũ.
 */
async function persistMatches(db: D1Database, tripId: string, results: MatchResult[]): Promise<void> {
  const stmt = db.prepare(
    `INSERT INTO matches (
       id, trip_id, order_id, score, distance_score, route_score,
       direction_score, vehicle_score, capacity_score, time_score,
       detour_km, reasons_json
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  );
  const statements = [
    db.prepare('DELETE FROM matches WHERE trip_id = ?').bind(tripId),
    ...results.map((r) => {
      const order = r.order;
      const c = r.components;
      return stmt.bind(
        crypto.randomUUID(), tripId, order.id, r.score,
        c.distance, c.route, c.direction, c.vehicle, c.capacity, c.time,
        r.detour_km, JSON.stringify(r.reasons),
      );
    }),
  ];
  await db.batch(statements);
}