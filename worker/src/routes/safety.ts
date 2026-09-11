import { Hono } from 'hono';
import type { AppEnv } from '../env';
import { ApiError } from '../lib/errors';
import { authMiddleware } from '../middleware/auth';
import {
  blockUser,
  createReport,
  unblockUser,
  validateReportInput,
} from '../services/safety';

/**
 * Safety routes (Phase 5 — plan §18 Trust layer).
 *  - POST /reports — báo cáo user khác
 *  - POST /blocks — chặn user
 *  - DELETE /blocks/:userId — bỏ chặn
 *
 * Lưu ý: tách 2 router riêng (reportRoutes/blocksRoutes) vì mount
 * app.route('/reports', X) + app.route('/blocks', X) với cùng X sẽ
 * tạo đường dẫn trùng lặp (/reports/reports...).
 */
export const reportRoutes = new Hono<AppEnv>();
export const blockRoutes = new Hono<AppEnv>();

reportRoutes.use('*', authMiddleware);
blockRoutes.use('*', authMiddleware);

reportRoutes.post('/', async (c) => {
  const body = await c.req.json().catch(() => null);
  const input = validateReportInput(body);
  const ip = c.req.header('CF-Connecting-IP') ?? '';
  const report = await createReport(c.env, c.get('userId'), input, ip);
  return c.json({ data: report }, 201);
});

blockRoutes.post('/', async (c) => {
  const body = (await c.req.json().catch(() => null)) as Record<string, unknown> | null;
  const blockedUserId = String(body?.target_user_id ?? '').trim();
  if (!blockedUserId) {
    throw new ApiError(400, 'INVALID_FIELD', 'Thiếu người cần chặn');
  }
  const ip = c.req.header('CF-Connecting-IP') ?? '';
  const result = await blockUser(c.env, c.get('userId'), blockedUserId, ip);
  return c.json({ data: result });
});

blockRoutes.delete('/:userId', async (c) => {
  const result = await unblockUser(c.env, c.get('userId'), c.req.param('userId'));
  return c.json({ data: result });
});