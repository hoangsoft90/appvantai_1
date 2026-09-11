import type { LatLng } from '../lib/geo';
import type { MapsProvider } from './provider';
import { makeTimeoutSignal, withResilience } from './resilience';

/**
 * Nominatim geocoding (plan §14 — geocoding primary, miễn phí).
 * Tuân thủ usage policy: tối đa 1 req/s, có User-Agent rõ ràng.
 * Kết quả phải được cache ở KV (geo:<query>) trước khi dùng tiếp.
 *
 * plan2_final §5.2: timeout + circuit breaker như OSRM.
 */
let lastCallMs = 0;
let inflight: Promise<void> = Promise.resolve();

/** Throttle tối thiểu 1.1s giữa các request (policy Nominatim). */
async function throttle(): Promise<void> {
  const prev = inflight;
  let release!: () => void;
  inflight = new Promise<void>((r) => (release = r));
  await prev;
  const wait = Math.max(0, 1100 - (Date.now() - lastCallMs));
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  lastCallMs = Date.now();
  release();
}

export function nominatimGeocoder(): MapsProvider['geocode'] {
  return async (query: string) => {
    await throttle();
    return withResilience(async (timeoutMs) => {
      const url =
        `https://nominatim.openstreetmap.org/search?format=json&limit=1` +
        `&countrycodes=vn&accept-language=vi&q=${encodeURIComponent(query)}`;
      const { signal, done } = makeTimeoutSignal(timeoutMs);
      try {
        const res = await fetch(url, {
          headers: {
            'User-Agent': 'appvantai-mvp/0.1 (pilot HN-HP corridor)',
            Accept: 'application/json',
          },
          signal,
        });
        if (!res.ok) {
          throw new Error(`Nominatim ${res.status}`);
        }
        const rows = (await res.json()) as {
          lat: string;
          lon: string;
          display_name: string;
        }[];
        if (rows.length === 0) {
          throw new Error('GEOCODE_NOT_FOUND');
        }
        const row = rows[0];
        return {
          point: { lat: Number(row.lat), lng: Number(row.lon) } as LatLng,
          label: row.display_name,
        };
      } finally {
        done();
      }
    });
  };
}
