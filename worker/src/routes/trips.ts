import { Hono } from 'hono';
import type { AppEnv } from '../env';
import { ApiError, Errors } from '../lib/errors';
import { getMapsProvider } from '../maps/provider';
import { requireLegalConsent } from '../services/authorization';
import { authMiddleware } from '../middleware/auth';
import { endTrip, startTrip, updateDriverLocation } from '../services/gps';
import {
  createTrip,
  getTrip,
  listTrips,
  findMatches,
} from '../services/trips';

export const trips = new Hono<AppEnv>();

function parseTripInput(body: unknown): {
  origin: { lat: number; lng: number };
  origin_address: string;
  destination: { lat: number; lng: number };
  destination_address: string;
} {
  const b = (body ?? {}) as Record<string, unknown>;
  const num = (v: unknown, field: string): number => {
    const n = Number(v);
    if (!Number.isFinite(n)) {
      throw Errors.badRequest('INVALID_FIELD', `${field} không hợp lệ`);
    }
    return n;
  };
  const from_lat = num(b.from_lat, 'from_lat');
  const from_lng = num(b.from_lng, 'from_lng');
  const to_lat = num(b.to_lat, 'to_lat');
  const to_lng = num(b.to_lng, 'to_lng');
  if (from_lat < -90 || from_lat > 90 || to_lat < -90 || to_lat > 90) {
    throw Errors.badRequest('INVALID_FIELD', 'Vĩ độ không hợp lệ');
  }
  if (from_lng < -180 || from_lng > 180 || to_lng < -180 || to_lng > 180) {
    throw Errors.badRequest('INVALID_FIELD', 'Kinh độ không hợp lệ');
  }
  return {
    origin: { lat: from_lat, lng: from_lng },
    origin_address: String(b.from_address ?? '').trim().slice(0, 200),
    destination: { lat: to_lat, lng: to_lng },
    destination_address: String(b.to_address ?? '').trim().slice(0, 200),
  };
}

trips.use('*', authMiddleware);

// plan2_final §1.4: consent enforce server-side cho mọi action driver (GET đọc only).
trips.use('*', async (c, next) => {
  if (c.req.method === 'GET') {
    await next();
    return;
  }
  await requireLegalConsent(c.env.DB, c.get('userId'));
  await next();
});

// POST /trips — driver starts a trip ("Tôi đang chạy")
trips.post('/', async (c) => {
  if (c.get('userRole') !== 'driver') {
    throw new ApiError(403, 'FORBIDDEN', 'Chỉ tài xế mới được tạo chuyến.');
  }

  const body = await c.req.json().catch(() => null);
  const input = parseTripInput(body);
  // plan2_final §4.1: trip_type 'return' = xe rỗng chiều đi, tìm hàng chiều về B→A.
  const tripTypeRaw = String((body as Record<string, unknown> | null)?.trip_type ?? 'one_way');
  if (tripTypeRaw !== 'one_way' && tripTypeRaw !== 'return') {
    throw Errors.badRequest('INVALID_TRIP_TYPE', 'trip_type phải là one_way hoặc return');
  }
  const maps = getMapsProvider(c.env);
  const trip = await createTrip(c.env, maps, c.get('userId'), input, tripTypeRaw as 'one_way' | 'return');
  return c.json({ data: trip }, 201);
});

// GET /trips — driver's trips (active first)
trips.get('/', async (c) => {
  const trips_ = await listTrips(c.env.DB, c.get('userId'));
  return c.json({ data: trips_ });
});

// POST /trips/:id/matches — run the matching pipeline ("quét radar")
trips.post('/:id/matches', async (c) => {
  if (c.get('userRole') !== 'driver') {
    throw new ApiError(403, 'FORBIDDEN', 'Chỉ tài xế mới được quét mối hàng.');
  }
  const id = c.req.param('id');
  const result = await findMatches(c.env, id, c.get('userId'));
  return c.json({ data: result });
});

// POST /trips/:id/start — bắt đầu chuyến (GPS bật, plan §13)
trips.post('/:id/start', async (c) => {
  if (c.get('userRole') !== 'driver') {
    throw new ApiError(403, 'FORBIDDEN', 'Chỉ tài xế mới thao tác chuyến.');
  }
  const id = c.req.param('id');
  const ip = c.req.header('CF-Connecting-IP') ?? '';
  const result = await startTrip(c.env, id, c.get('userId'), ip);
  return c.json({ data: result });
});

// POST /trips/:id/end — kết thúc chuyến (ngừng track GPS)
trips.post('/:id/end', async (c) => {
  if (c.get('userRole') !== 'driver') {
    throw new ApiError(403, 'FORBIDDEN', 'Chỉ tài xế mới thao tác chuyến.');
  }
  const id = c.req.param('id');
  const ip = c.req.header('CF-Connecting-IP') ?? '';
  const result = await endTrip(c.env, id, c.get('userId'), ip);
  return c.json({ data: result });
});

// POST /trips/:id/location — driver gửi GPS (KV, throttle 30s)
// plan2_final §6.1: CHỈ trip planned/active của ĐÚNG driver mới nhận location.
trips.post('/:id/location', async (c) => {
  if (c.get('userRole') !== 'driver') {
    throw new ApiError(403, 'FORBIDDEN', 'Chỉ tài xế mới gửi vị trí.');
  }
  const id = c.req.param('id');
  const trip = await getTrip(c.env.DB, c.get('userId'), id);
  // plan3_final Mục 3 — GPS chỉ khi trip active: planned chưa start (chưa có
  // vị trí để track), ended/cancelled đã xóa KV. Reject rõ ràng từng trường hợp.
  if (trip.status === 'planned') {
    throw Errors.badRequest('TRIP_NOT_ACTIVE', 'Chuyến chưa bắt đầu — hãy start chuyến trước khi gửi vị trí');
  }
  if (trip.status === 'ended' || trip.status === 'cancelled') {
    throw Errors.badRequest('TRIP_NOT_ACTIVE', 'Chuyến đã kết thúc — không nhận vị trí nữa');
  }
  const body = (await c.req.json().catch(() => null)) as Record<string, unknown> | null;
  const lat = Number(body?.lat);
  const lng = Number(body?.lng);
  if (!Number.isFinite(lat) || lat < -90 || lat > 90 || !Number.isFinite(lng) || lng < -180 || lng > 180) {
    throw Errors.badRequest('INVALID_COORD', 'Tọa độ không hợp lệ');
  }
  const result = await updateDriverLocation(c.env.APP_KV, c.get('userId'), lat, lng);
  return c.json({ data: result });
});

// GET /trips/:id — trip detail
trips.get('/:id', async (c) => {
  const id = c.req.param('id');
  const trip = await getTrip(c.env.DB, c.get('userId'), id);
  return c.json({ data: trip });
});