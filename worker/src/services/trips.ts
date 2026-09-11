import type { Env } from '../env';
import type { MapsProvider } from '../maps/provider';
import { getMapsProvider } from '../maps/provider';
import { Errors } from '../lib/errors';
import { encodePolyline } from '../lib/geo';
import type { LatLng } from '../lib/geo';
import { runMatching, type MatchResult } from './matching';
import { geocodeWithCache, getCachedRoute } from './route_cache';

/**
 * Trips (Phase 3 — plan §5.1, §11).
 * Tài xế nhập origin/destination (địa chỉ hoặc tọa độ) → geocode + route
 * (có cache) → lưu trips với polyline. Matching (Phase 3 core) đọc polyline này.
 */

export type TripStatus = 'planned' | 'active' | 'ended' | 'cancelled';
export type TripType = 'one_way' | 'return';

export interface Trip {
  id: string;
  driver_id: string;
  origin_lat: number;
  origin_lng: number;
  origin_address: string;
  destination_lat: number;
  destination_lng: number;
  destination_address: string;
  route_polyline: string;
  distance_m: number;
  duration_s: number;
  direction: string;
  trip_type: TripType;
  status: TripStatus;
  started_at: string | null;
  ended_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface TripInput {
  origin: LatLng;
  origin_address: string;
  destination: LatLng;
  destination_address: string;
}

const TRIP_COLS = `
  id, driver_id, origin_lat, origin_lng, origin_address,
  destination_lat, destination_lng, destination_address,
  route_polyline, distance_m, duration_s, direction, trip_type, status,
  started_at, ended_at, created_at, updated_at
`;

/** Rate limit tạo chuyến: 20/giờ (tránh spam geocode+route tốn API maps). */
export async function enforceTripRateLimit(kv: KVNamespace, driverId: string): Promise<void> {
  const key = `triprl:${driverId}`;
  const count = Number((await kv.get(key)) ?? '0');
  if (count >= 20) {
    throw Errors.tooManyRequests('TRIP_RATE_LIMITED', 'Quá nhiều chuyến được tạo trong thời gian ngắn, vui lòng thử lại sau');
  }
  await kv.put(key, String(count + 1), { expirationTtl: 3600 });
}

export async function createTrip(
  env: Env,
  maps: MapsProvider,
  driverId: string,
  input: TripInput,
  tripType: TripType = 'one_way',
): Promise<Trip> {
  await enforceTripRateLimit(env.APP_KV, driverId);
  const route = await getCachedRoute(env.DB, maps, input.origin, input.destination);
  const id = crypto.randomUUID();
  await env.DB
    .prepare(
      `INSERT INTO trips (
         id, driver_id, origin_lat, origin_lng, origin_address,
         destination_lat, destination_lng, destination_address,
         route_polyline, distance_m, duration_s, direction, trip_type, status
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'one_way', ?, 'planned')`,
    )
    .bind(
      id, driverId,
      input.origin.lat, input.origin.lng, input.origin_address,
      input.destination.lat, input.destination.lng, input.destination_address,
      encodePolyline(route.polyline), route.distance_m, route.duration_s,
      tripType,
    )
    .run();
  const trip = await getTripById(env.DB, driverId, id);
  if (!trip) throw Errors.internal('Không thể tạo chuyến');
  return trip;
}

export async function listTrips(db: D1Database, driverId: string): Promise<Trip[]> {
  const rows = await db
    .prepare(`SELECT ${TRIP_COLS} FROM trips WHERE driver_id = ? ORDER BY created_at DESC LIMIT 20`)
    .bind(driverId)
    .all<Trip>();
  return rows.results ?? [];
}

export async function getTripById(db: D1Database, driverId: string, id: string): Promise<Trip | null> {
  const row = await db
    .prepare(`SELECT ${TRIP_COLS} FROM trips WHERE id = ? AND driver_id = ?`)
    .bind(id, driverId)
    .first<Trip>();
  return row ?? null;
}

/** Lấy chuyến của đúng driver, 404 nếu không thuộc về họ. */
export async function getTrip(db: D1Database, driverId: string, id: string): Promise<Trip> {
  const trip = await getTripById(db, driverId, id);
  if (!trip) throw Errors.notFound('TRIP_NOT_FOUND', 'Chuyến không tồn tại');
  return trip;
}

/**
 * Chạy matching pipeline (plan §5) cho một chuyến của driver.
 * Trả về kết quả đã lưu vào bảng matches (cho funnel metrics §29).
 */
export async function findMatches(env: Env, tripId: string, driverId: string): Promise<MatchResult[]> {
  const trip = await getTrip(env.DB, driverId, tripId);
  if (trip.status === 'ended' || trip.status === 'cancelled') {
    throw Errors.badRequest('TRIP_NOT_ACTIVE', 'Chuyến đã kết thúc hoặc bị hủy');
  }
  const maps = getMapsProvider(env);
  return runMatching(env, maps, trip);
}