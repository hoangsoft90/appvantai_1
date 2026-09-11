import { Hono } from 'hono';
import type { AppEnv } from '../env';
import { ApiError, Errors } from '../lib/errors';
import { authMiddleware } from '../middleware/auth';
import { writeAuditLog } from '../services/audit';

/**
 * Admin moderation (Phase 5 — plan §3.3, §18).
 * Role 'admin' mới được dùng. P0 tối giản:
 *  - GET /admin/reports — danh sách report (open trước)
 *  - POST /admin/reports/:id/resolve — đóng report
 *  - POST /admin/users/:id/suspend — treo user
 *  - POST /admin/users/:id/ban — cấm vĩnh viễn
 */
export const adminRoutes = new Hono<AppEnv>();

adminRoutes.use('*', authMiddleware);

function requireAdmin(c: { get(key: 'userRole'): string }): void {
  if (c.get('userRole') !== 'admin') {
    throw new ApiError(403, 'FORBIDDEN', 'Chỉ admin mới được dùng chức năng này');
  }
}

adminRoutes.get('/reports', async (c) => {
  requireAdmin(c);
  const status = c.req.query('status') ?? 'open';
  const rows = await c.env.DB
    .prepare(
      `SELECT id, reporter_id, target_user_id, order_id, reason, description, status, created_at
       FROM reports WHERE status = ? ORDER BY created_at DESC LIMIT 100`,
    )
    .bind(status)
    .all();
  return c.json({ data: rows.results ?? [] });
});

adminRoutes.post('/reports/:id/resolve', async (c) => {
  requireAdmin(c);
  await c.env.DB
    .prepare(`UPDATE reports SET status = 'resolved' WHERE id = ?`)
    .bind(c.req.param('id'))
    .run();
  await writeAuditLog(c.env, {
    actorId: c.get('userId'),
    entityType: 'report',
    entityId: c.req.param('id'),
    action: 'report_resolve',
    ip: c.req.header('CF-Connecting-IP') ?? '',
  });
  return c.json({ data: { ok: true } });
});

adminRoutes.post('/users/:id/suspend', async (c) => {
  requireAdmin(c);
  const targetId = c.req.param('id');
  const res = await c.env.DB
    .prepare(`UPDATE users SET status = 'suspended', updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?`)
    .bind(targetId)
    .run();
  if (res.meta.changes === 0) throw Errors.notFound('USER_NOT_FOUND', 'Người dùng không tồn tại');
  await writeAuditLog(c.env, {
    actorId: c.get('userId'),
    entityType: 'user',
    entityId: targetId,
    action: 'suspend',
    ip: c.req.header('CF-Connecting-IP') ?? '',
  });
  return c.json({ data: { ok: true } });
});

adminRoutes.post('/users/:id/ban', async (c) => {
  requireAdmin(c);
  const targetId = c.req.param('id');
  const res = await c.env.DB
    .prepare(`UPDATE users SET status = 'banned', updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?`)
    .bind(targetId)
    .run();
  if (res.meta.changes === 0) throw Errors.notFound('USER_NOT_FOUND', 'Người dùng không tồn tại');
  await writeAuditLog(c.env, {
    actorId: c.get('userId'),
    entityType: 'user',
    entityId: targetId,
    action: 'ban',
    ip: c.req.header('CF-Connecting-IP') ?? '',
  });
  return c.json({ data: { ok: true } });
});