import { Hono } from 'hono';
import type { AppEnv } from '../env';
import { Errors } from '../lib/errors';
import { requireLegalConsent } from '../services/authorization';
import { authMiddleware } from '../middleware/auth';
import { geocodeWithCache } from '../services/route_cache';
import { getMapsProvider } from '../maps/provider';

/**
 * Maps endpoints (plan2_final §5.1 — Address search / geocode).
 * GET /maps/geocode?q=<address> → { point, label }
 * Client dùng để search địa chỉ thay vì nhập lat/lng thủ công.
 * Cache KV tự động (geocodeWithCache — 30 ngày) để tôn trọng Nominatim 1 req/s.
 */
export const mapsRoutes = new Hono<AppEnv>();

mapsRoutes.use('*', authMiddleware);

mapsRoutes.get('/geocode', async (c) => {
  const q = (c.req.query('q') ?? '').trim();
  if (q.length < 3) {
    throw Errors.badRequest('INVALID_QUERY', 'Từ khóa địa chỉ phải có ít nhất 3 ký tự');
  }
  if (q.length > 200) {
    throw Errors.badRequest('INVALID_QUERY', 'Từ khóa địa chỉ quá dài (tối đa 200 ký tự)');
  }
  await requireLegalConsent(c.env.DB, c.get('userId'));
  const maps = getMapsProvider(c.env);
  try {
    const result = await geocodeWithCache(c.env.APP_KV, maps, q);
    return c.json({ data: result });
  } catch {
    throw Errors.badRequest('GEOCODE_FAILED', 'Không tìm thấy địa chỉ, vui lòng thử từ khóa khác');
  }
});
