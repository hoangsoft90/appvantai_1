import { decodePolyline } from '../lib/geo';
import type { LatLng } from '../lib/geo';
import { makeTimeoutSignal, withResilience } from './resilience';
import type { MapsProvider } from './provider';

/**
 * OSRM routing (plan §14 — primary, miễn phí).
 * Public server: https://router.project-osrm.org (không giới hạn cứng).
 * Mọi kết quả phải được cache ở route_cache (D1) trước khi dùng tiếp.
 *
 * plan2_final §5.2: timeout 10s + circuit breaker — không request treo vô hạn,
 * provider liên tục lỗi → fail-fast, không treo matching.
 */
export function osrmRouter(): MapsProvider['route'] {
  return async (from: LatLng, to: LatLng) => {
    return withResilience(async (timeoutMs) => {
      const url =
        `https://router.project-osrm.org/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}` +
        `?overview=full&geometries=polyline6&steps=false`;
      const { signal, done } = makeTimeoutSignal(timeoutMs);
      try {
        const res = await fetch(url, {
          signal,
          // Cloudflare Workers fetch mặc định không gửi User-Agent → một số
          // public OSRM server trả 403. Gửi UA rõ ràng như browser.
          headers: { 'User-Agent': 'appvantai-mvp/0.1' },
        });
        if (!res.ok) {
          throw new Error(`OSRM ${res.status}`);
        }
        const data = (await res.json()) as {
          code: string;
          routes?: { geometry: string; distance: number; duration: number }[];
        };
        if (data.code !== 'Ok' || !data.routes || data.routes.length === 0) {
          throw new Error(`OSRM no route (${data.code})`);
        }
        const r = data.routes[0];
        return {
          polyline: decodePolyline(r.geometry),
          distance_m: Math.round(r.distance),
          duration_s: Math.round(r.duration),
        };
      } finally {
        done();
      }
    });
  };
}
