import { haversineKm } from '../lib/geo';
import type { LatLng } from '../lib/geo';
import type { MapsProvider } from './provider';

/**
 * Mock MapsProvider — deterministic, không cần network.
 * Dùng khi MAPS_PROVIDER=mock (wrangler.toml dev) và trong test:
 *  - geocode: tra cứu bảng địa danh VN (corridor pilot HN → HP), fallback (21.0, 105.85)
 *  - route: polyline 3 điểm (đi qua midpoint), distance = haversine × 1.3 (road factor),
 *    duration = distance / 45 km/h.
 */
const PLACES: Record<string, LatLng> = {
  'hà nội': { lat: 21.0285, lng: 105.8542 },
  'hanoi': { lat: 21.0285, lng: 105.8542 },
  'hải phòng': { lat: 20.8449, lng: 106.6881 },
  'haiphong': { lat: 20.8449, lng: 106.6881 },
  'hải dương': { lat: 20.941, lng: 106.311 },
  'haiduong': { lat: 20.941, lng: 106.311 },
  'hưng yên': { lat: 20.646, lng: 106.051 },
  'hung yen': { lat: 20.646, lng: 106.051 },
  'bắc ninh': { lat: 21.186, lng: 106.076 },
  'bac ninh': { lat: 21.186, lng: 106.076 },
  'thái bình': { lat: 20.446, lng: 106.332 },
  'thai binh': { lat: 20.446, lng: 106.332 },
};

export function mockProvider(): MapsProvider {
  return {
    async geocode(query: string) {
      const q = query.toLowerCase().trim();
      const key = Object.keys(PLACES).find((k) => q.includes(k));
      const point = key ? PLACES[key] : { lat: 21.0, lng: 105.85 };
      return { point, label: key ? query : query };
    },

    async route(from: LatLng, to: LatLng) {
      const mid = {
        lat: (from.lat + to.lat) / 2 + 0.01, // hơi lệch để corridor không thẳng hàng
        lng: (from.lng + to.lng) / 2 + 0.005,
      };
      const polyline = [from, mid, to];
      const distance_m = Math.round(haversineKm(from, to) * 1000 * 1.3);
      const duration_s = Math.round(distance_m / (45 / 3.6));
      return { polyline, distance_m, duration_s };
    },
  };
}