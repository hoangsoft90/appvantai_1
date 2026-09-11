import type { Env } from '../env';
import type { LatLng } from '../lib/geo';
import { mockProvider } from './mock';
import { nominatimGeocoder } from './nominatim';
import { osrmRouter } from './osrm';

/**
 * MapsProvider abstraction (plan §14) — không hard-code business logic
 * vào một provider.
 *  - geocode(): địa chỉ → lat/lng (Nominatim; fallback mock khi dev)
 *  - route(): route thực tế → polyline + distance + duration (OSRM)
 *
 * Local math (Haversine/point-to-line) nằm ở lib/geo.ts, không thuộc provider.
 */
export interface MapsProvider {
  geocode(query: string): Promise<{ point: LatLng; label: string }>;
  route(from: LatLng, to: LatLng): Promise<{ polyline: LatLng[]; distance_m: number; duration_s: number }>;
}

export function getMapsProvider(env: Env): MapsProvider {
  const mode = (env.MAPS_PROVIDER ?? 'osrm').toLowerCase();
  if (mode === 'mock') return mockProvider();
  return {
    geocode: nominatimGeocoder(),
    route: osrmRouter(),
  };
}