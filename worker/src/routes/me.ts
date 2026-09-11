import { Hono } from 'hono';
import type { AppEnv, Env } from '../env';
import { Errors } from '../lib/errors';
import { authMiddleware } from '../middleware/auth';
import { writeAuditLog } from '../services/audit';
import {
  ensureDriverProfile,
  getDriverProfile,
  upsertDriverProfile,
  validateVehicleInput,
} from '../services/profiles';
import { getUserById, toPublicUser, updateUser } from '../services/users';

/**
 * /me + /me/vehicle (Phase 1 — Identity).
 * Lưu ý: plan §25 đề xuất /vehicles/:id nhưng plan §11 chỉ có driver_profiles
 * (1 tài xế = 1 xe) và §2.2 loại fleet management → dùng /me/vehicle cho gọn.
 */

/**
 * plan3_final Mục 1 + plan4_final §3 — Khóa role theo business state:
 *  - accepted/pickup/in_transit/delivered: LUÔN tính là đang hoạt động
 *    (chuyến hàng đang chạy — KHÔNG phụ thuộc expires_at, đơn hết cửa sổ
 *    lấy hàng vẫn phải chạy tiếp).
 *  - posted/matched/contacted: tính khi chưa quá expires_at (đơn hết hạn
 *    thật sự thì không chặn — lazy expiry coi như đã xong).
 *  - Trip (driver): giữ nguyên chặn khi planned/active.
 */
const HARD_ACTIVE_ORDER_STATUSES = "('accepted','pickup','in_transit','delivered')";
const SOFT_ACTIVE_ORDER_STATUSES = "('posted','matched','contacted')";

async function assertRoleChangeAllowed(env: Env, userId: string): Promise<void> {
  const now = new Date().toISOString();
  const orders = await env.DB.prepare(
    `SELECT
       SUM(CASE WHEN status IN ${HARD_ACTIVE_ORDER_STATUSES} THEN 1 ELSE 0 END) AS n_hard,
       SUM(CASE WHEN status IN ${SOFT_ACTIVE_ORDER_STATUSES} AND expires_at > ? THEN 1 ELSE 0 END) AS n_soft
     FROM cargo_orders WHERE customer_id = ?`,
  )
    .bind(now, userId)
    .first<{ n_hard: number | null; n_soft: number | null }>();
  if ((orders?.n_hard ?? 0) > 0 || (orders?.n_soft ?? 0) > 0) {
    throw Errors.conflict('ROLE_LOCKED', 'Không thể đổi vai trò khi đang có đơn/chuyến đang hoạt động');
  }
  const trips = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM trips WHERE driver_id = ? AND status IN ('planned','active')`,
  )
    .bind(userId)
    .first<{ n: number }>();
  if ((trips?.n ?? 0) > 0) {
    throw Errors.conflict('ROLE_LOCKED', 'Không thể đổi vai trò khi đang có đơn/chuyến đang hoạt động');
  }
}

export const meRoutes = new Hono<AppEnv>();

meRoutes.use('*', authMiddleware);

meRoutes.get('/', async (c) => {
  const user = await getUserById(c.env.DB, c.get('userId'));
  if (!user) {
    throw Errors.unauthorized('USER_NOT_FOUND', 'Người dùng không tồn tại');
  }
  const profile = user.role === 'driver' ? await getDriverProfile(c.env.DB, user.id) : null;
  // legal_consent_at: client cần biết để gate form tạo đơn / nhận đơn (§18)
  return c.json({ user: toPublicUser(user), driver_profile: profile, legal_consent_at: user.legal_consent_at });
});

meRoutes.patch('/', async (c) => {
  const body = (await c.req.json().catch(() => null)) as Record<string, unknown> | null;
  const user = await getUserById(c.env.DB, c.get('userId'));
  if (!user) {
    throw Errors.unauthorized('USER_NOT_FOUND', 'Người dùng không tồn tại');
  }

  const patch: { name?: string; role?: 'driver' | 'customer' } = {};
  let touched = false;

  if (body?.name !== undefined) {
    const name = String(body.name).trim();
    if (name.length < 2 || name.length > 100) {
      throw Errors.badRequest('INVALID_NAME', 'Tên phải từ 2 đến 100 ký tự');
    }
    patch.name = name;
    touched = true;
  }
  if (body?.role !== undefined) {
    const role = String(body.role);
    if (role !== 'driver' && role !== 'customer') {
      throw Errors.badRequest('INVALID_ROLE', 'Vai trò phải là driver hoặc customer');
    }
    // plan3_final Mục 1 — role chỉ chọn 1 lần: re-submit cùng role (onboarding
    // bấm lại) vẫn cho qua; đổi role khác → chặn nếu đang có đơn/chuyến active.
    if (role !== user.role) {
      await assertRoleChangeAllowed(c.env, user.id);
    }
    patch.role = role;
    touched = true;
  }
  if (!touched) {
    throw Errors.badRequest('INVALID_REQUEST', 'Không có trường nào để cập nhật');
  }

  const updated = await updateUser(c.env.DB, user.id, patch);
  if (!updated) {
    throw Errors.unauthorized('USER_NOT_FOUND', 'Người dùng không tồn tại');
  }
  // Chọn vai trò driver → đảm bảo có driver_profile (rỗng, điền xe sau)
  const profile = updated.role === 'driver' ? await ensureDriverProfile(c.env.DB, updated.id) : null;
  return c.json({ user: toPublicUser(updated), driver_profile: profile });
});

meRoutes.get('/vehicle', async (c) => {
  const profile = await getDriverProfile(c.env.DB, c.get('userId'));
  if (!profile) {
    throw Errors.notFound('NO_DRIVER_PROFILE', 'Chưa có hồ sơ tài xế');
  }
  return c.json({ driver_profile: profile });
});

meRoutes.patch('/vehicle', async (c) => {
  const body = await c.req.json().catch(() => null);
  const input = validateVehicleInput(body);
  const profile = await upsertDriverProfile(c.env.DB, c.get('userId'), input);
  return c.json({ driver_profile: profile });
});

// POST /me/legal-consent — tick disclaimer (Phase 5, plan §18):
// bắt buộc trước khi tạo đơn / nhận đơn; lưu thời gian + IP vào audit_logs.
meRoutes.post('/legal-consent', async (c) => {
  const user = await getUserById(c.env.DB, c.get('userId'));
  if (!user) {
    throw Errors.unauthorized('USER_NOT_FOUND', 'Người dùng không tồn tại');
  }
  if (user.legal_consent_at) {
    return c.json({ user: toPublicUser(user), legal_consent_at: user.legal_consent_at });
  }
  const now = new Date().toISOString();
  await c.env.DB
    .prepare(`UPDATE users SET legal_consent_at = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?`)
    .bind(now, user.id)
    .run();
  const ip = c.req.header('CF-Connecting-IP') ?? '';
  await writeAuditLog(c.env, {
    actorId: user.id,
    entityType: 'user',
    entityId: user.id,
    action: 'legal_consent',
    metadata: { consented_at: now, text: 'disclaimer_v1' },
    ip,
  });
  const updated = await getUserById(c.env.DB, user.id);
  return c.json({ user: toPublicUser(updated!), legal_consent_at: now });
});