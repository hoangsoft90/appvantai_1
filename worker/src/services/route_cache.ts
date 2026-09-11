import type { MapsProvider } from '../maps/provider';
import { decodePolyline, encodePolyline } from '../lib/geo';
import type { LatLng } from '../lib/geo';

/**
 * Caching theo plan §14: geocode 1 lần + route 1 lần → cache → dùng lại.
 *  - Route: D1 route_cache (key là tọa độ làm tròn ~11m)
 *  - Geocode: KV (geo:<query>) — tránh phí D1 writes không cần thiết
 */
const CACHE_TTL_DAYS = 30;
const GEOCODE_TTL_SECONDS = 30 * 24 * 3600;

export function coordKey(p: LatLng): string {
  return `${p.lat.toFixed(4)},${p.lng.toFixed(4)}`;
}

function iso(daysFromNow: number): string {
  return new Date(Date.now() + daysFromNow * 24 * 3600 * 1000).toISOString();
}

export interface CachedRoute {
  polyline: LatLng[];
  distance_m: number;
  duration_s: number;
}

/** Route có cache (D1). Fallback: vẫn trả kết quả tươi nếu cache thất bại. */
export async function getCachedRoute(
  db: D1Database,
  maps: MapsProvider,
  from: LatLng,
  to: LatLng,
): Promise<CachedRoute> {
  const ok = coordKey(from);
  const dk = coordKey(to);
  const now = new Date().toISOString();
  const row = await db
    .prepare(
      `SELECT polyline, distance_m, duration_s FROM route_cache
       WHERE origin_key = ? AND destination_key = ? AND expires_at > ?`,
    )
    .bind(ok, dk, now)
    .first<{ polyline: string; distance_m: number; duration_s: number }>();
  if (row) {
    return {
      polyline: decodePolyline(row.polyline),
      distance_m: row.distance_m,
      duration_s: row.duration_s,
    };
  }

  const r = await maps.route(from, to);
  try {
    await db
      .prepare(
        `INSERT INTO route_cache (origin_key, destination_key, provider, polyline, distance_m, duration_s, expires_at)
         VALUES (?, ?, 'osrm', ?, ?, ?, ?)
         ON CONFLICT(origin_key, destination_key) DO UPDATE SET
           polyline = excluded.polyline,
           distance_m = excluded.distance_m,
           duration_s = excluded.duration_s,
           expires_at = excluded.expires_at`,
      )
      .bind(ok, dk, encodePolyline(r.polyline), r.distance_m, r.duration_s, iso(CACHE_TTL_DAYS))
      .run();
  } catch {
    // Cache thất bại không chặn luồng chính
  }
  return r;
}

/** Geocode có cache (KV). */
export async function geocodeWithCache(
  kv: KVNamespace,
  maps: MapsProvider,
  query: string,
): Promise<{ point: LatLng; label: string }> {
  const key = `geo:${query.toLowerCase().trim()}`;
  const cached = await kv.get(key);
  if (cached) {
    try {
      return JSON.parse(cached) as { point: LatLng; label: string };
    } catch {
      // cache hỏng → geocode lại
    }
  }
  const r = await maps.geocode(query);
  try {
    await kv.put(key, JSON.stringify(r), { expirationTtl: GEOCODE_TTL_SECONDS });
  } catch {
    // bỏ qua
  }
  return r;
}