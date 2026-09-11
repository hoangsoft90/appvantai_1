/**
 * Local math (plan §14): sau khi có polyline, MỌI tính toán pickup→route
 * đều dùng Haversine + point-to-line projection — KHÔNG gọi API.
 */

export interface LatLng {
  lat: number;
  lng: number;
}

const EARTH_RADIUS_M = 6_371_000;

export function haversineKm(a: LatLng, b: LatLng): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(s)) / 1000;
}

/** Bearing (độ, 0-360) từ a tới b. */
export function bearingDeg(a: LatLng, b: LatLng): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const toDeg = (d: number) => (d * 180) / Math.PI;
  const φ1 = toRad(a.lat);
  const φ2 = toRad(b.lat);
  const Δλ = toRad(b.lng - a.lng);
  const y = Math.sin(Δλ) * Math.cos(φ2);
  const x = Math.cos(φ1) * Math.sin(φ2) - Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

/** Chênh lệch góc giữa 2 bearing, chuẩn hóa về [0, 180]. */
export function bearingDiffDeg(a: number, b: number): number {
  const d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
}

/** Khoảng cách từ p tới segment a-b (km), dùng equirectangular projection + haversine. */
export function distanceToSegmentKm(p: LatLng, a: LatLng, b: LatLng): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const cosLat = Math.cos(toRad((a.lat + b.lat) / 2));
  const scale = EARTH_RADIUS_M * toRad(1);
  const ax = a.lng * cosLat * scale;
  const ay = a.lat * scale;
  const bx = b.lng * cosLat * scale;
  const by = b.lat * scale;
  const px = p.lng * cosLat * scale;
  const py = p.lat * scale;

  const dx = bx - ax;
  const dy = by - ay;
  const lenSq = dx * dx + dy * dy;
  let t = lenSq === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / lenSq;
  t = Math.max(0, Math.min(1, t));
  const proj = { lat: (ay + t * dy) / scale, lng: (ax + t * dx) / (cosLat * scale) };
  return haversineKm(p, proj);
}

/** Khoảng cách từ p tới polyline (mảng điểm), km. */
export function distanceToPolylineKm(p: LatLng, polyline: LatLng[]): number {
  let best = Infinity;
  for (let i = 0; i + 1 < polyline.length; i++) {
    const d = distanceToSegmentKm(p, polyline[i], polyline[i + 1]);
    if (d < best) best = d;
  }
  if (polyline.length === 1) return haversineKm(p, polyline[0]);
  return best === Infinity ? haversineKm(p, polyline[0]) : best;
}

/** Decode polyline6 (precision 1e6) thành mảng LatLng. */
export function decodePolyline(encoded: string): LatLng[] {
  const points: LatLng[] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    let result = 0;
    let shift = 0;
    let byte: number;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const dLat = result & 1 ? ~(result >> 1) : result >> 1;
    lat += dLat;

    result = 0;
    shift = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const dLng = result & 1 ? ~(result >> 1) : result >> 1;
    lng += dLng;

    points.push({ lat: lat / 1e6, lng: lng / 1e6 });
  }
  return points;
}

/** Encode polyline6 (cho mock/echo khi cần). */
export function encodePolyline(points: LatLng[]): string {
  let encoded = '';
  let prevLat = 0;
  let prevLng = 0;
  for (const p of points) {
    const lat = Math.round(p.lat * 1e6);
    const lng = Math.round(p.lng * 1e6);
    const dLat = lat - prevLat;
    const dLng = lng - prevLng;
    prevLat = lat;
    prevLng = lng;
    encoded += _encodeSigned(dLat) + _encodeSigned(dLng);
  }
  return encoded;
}

function _encodeSigned(v: number): string {
  let value = v < 0 ? ~(v << 1) : v << 1;
  let out = '';
  while (value >= 0x20) {
    out += String.fromCharCode((0x20 | (value & 0x1f)) + 63);
    value >>= 5;
  }
  out += String.fromCharCode(value + 63);
  return out;
}

/**
 * Resample polyline theo khoảng cách (mét) để corridor check nhanh và đều.
 * Luôn giữ điểm đầu/cuối; giới hạn số điểm để tránh tốn CPU.
 */
export function resamplePolyline(points: LatLng[], intervalM = 300, maxPoints = 2000): LatLng[] {
  if (points.length <= 2) return points;
  const out: LatLng[] = [points[0]];
  let carried = 0;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1];
    const b = points[i];
    const segM = haversineKm(a, b) * 1000;
    if (segM <= 0) continue;
    const cosLat = Math.cos((a.lat + b.lat) / 2 / 57.2958);
    const steps = Math.max(1, Math.floor((carried + segM) / intervalM));
    for (let s = 1; s <= steps; s++) {
      const t = Math.min(1, (s * intervalM - carried) / segM);
      out.push({
        lat: a.lat + (b.lat - a.lat) * t,
        lng: a.lng + (b.lng - a.lng) * t,
      });
      if (out.length >= maxPoints) return out;
    }
    carried = (carried + segM) % intervalM;
  }
  out.push(points[points.length - 1]);
  return out;
}