import type { Context, Next } from 'hono';
import { verify } from 'hono/jwt';
import { ApiError, Errors } from '../lib/errors';
import { getUserById } from '../services/users';

/**
 * Auth middleware: kiểm tra Bearer JWT (HS256, ký bằng JWT_SECRET).
 * Token do chính Worker phát hành sau khi verify OTP (Phase 0).
 * Khi gắn Firebase/Zalo sau này, chỉ cần thay phần verify này —
 * API surface không đổi.
 */
export async function authMiddleware(c: Context, next: Next): Promise<void> {
  const header = c.req.header('Authorization');
  if (!header?.startsWith('Bearer ')) {
    throw Errors.unauthorized();
  }
  const token = header.slice('Bearer '.length).trim();
  if (!token) {
    throw Errors.unauthorized();
  }
  try {
    const payload = await verify(token, c.env.JWT_SECRET, 'HS256');
    const sub = payload.sub;
    if (typeof sub !== 'string') {
      throw Errors.unauthorized('INVALID_TOKEN', 'Token không hợp lệ');
    }
    // Role đọc từ DB (single source of truth) — JWT chỉ là bằng chứng danh tính.
    // Nếu user đổi role qua PATCH /me, token cũ KHÔNG được dùng role cũ (bug stale role).
    const user = await getUserById(c.env.DB, sub);
    if (!user || user.status !== 'active') {
      throw Errors.unauthorized('USER_NOT_FOUND', 'Người dùng không tồn tại hoặc đã bị khóa');
    }
    c.set('userId', sub);
    c.set('userRole', user.role);
    await next();
  } catch (e) {
    if (e instanceof ApiError) throw e;
    throw Errors.unauthorized('INVALID_TOKEN', 'Token không hợp lệ hoặc đã hết hạn');
  }
}