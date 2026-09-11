import { Hono } from 'hono';
import { sign } from 'hono/jwt';
import type { AppEnv } from '../env';
import { Errors } from '../lib/errors';
import { log } from '../lib/logger';
import { normalizePhone } from '../lib/phone';
import { requestOtp, verifyOtp } from '../services/otp';
import { verifyFirebaseIdToken } from '../services/firebase_auth';
import { setFirebaseUid, toPublicUser, upsertUserByPhone } from '../services/users';

const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 ngày

export const authRoutes = new Hono<AppEnv>();

interface OtpBody {
  phone?: unknown;
}

interface VerifyBody extends OtpBody {
  otp?: unknown;
}

authRoutes.post('/request-otp', async (c) => {
  const body = (await c.req.json().catch(() => null)) as OtpBody | null;
  const phone = normalizePhone(String(body?.phone ?? ''));
  if (!phone) {
    throw Errors.badRequest('INVALID_PHONE', 'Số điện thoại không hợp lệ');
  }
  const code = await requestOtp(c.env.APP_KV, phone);
  // plan4_final §2: dev OTP chỉ khi ĐÚNG dev mode — APP_ENV=production (hoặc env
  // khác) thì ALLOW_DEV_OTP bị ÉP FALSE, response không bao giờ chứa dev_otp
  // (không phụ thuộc ai đặt var gì khi deploy). Env guard vẫn log lỗi cấu hình.
  const allowDev = c.env.APP_ENV === 'dev' && c.env.ALLOW_DEV_OTP === 'true';
  log('info', 'otp_requested', { requestId: c.get('requestId'), phone, dev: allowDev });
  return c.json({
    ok: true,
    // Chỉ trả OTP khi dev mode — production KHÔNG bao giờ echo mã này
    ...(allowDev ? { dev_otp: code } : {}),
  });
});

authRoutes.post('/verify-otp', async (c) => {
  const body = (await c.req.json().catch(() => null)) as VerifyBody | null;
  const phone = normalizePhone(String(body?.phone ?? ''));
  const otp = String(body?.otp ?? '').trim();
  if (!phone || !/^\d{6}$/.test(otp)) {
    throw Errors.badRequest('INVALID_REQUEST', 'Số điện thoại hoặc mã OTP không hợp lệ');
  }
  await verifyOtp(c.env.APP_KV, phone, otp);

  const user = await upsertUserByPhone(c.env.DB, phone);
  const now = Math.floor(Date.now() / 1000);
  const token = await sign(
    { sub: user.id, role: user.role, phone, exp: now + TOKEN_TTL_SECONDS },
    c.env.JWT_SECRET,
  );
  log('info', 'user_logged_in', { requestId: c.get('requestId'), userId: user.id });
  return c.json({ token, user: toPublicUser(user) });
});

// P0: JWT stateless — logout = client xóa token. Endpoint này giữ parity
// với API surface (plan §25) và là nơi gắn KV blocklist khi cần sau này.
authRoutes.post('/logout', (c) => {
  return c.json({ ok: true });
});

interface FirebaseVerifyBody {
  id_token?: unknown;
}

// Phase 7 §7.1 — Firebase Phone Auth (login production).
// Mobile: Firebase SDK gửi SMS thật + tự xác minh mã → lấy ID token → POST về đây.
// Worker KHÔNG tự phát SMS production; dev OTP chỉ tồn tại ở APP_ENV=dev.
// Response contract giống /auth/verify-otp → mobile lưu token như cũ.
authRoutes.post('/firebase', async (c) => {
  const body = (await c.req.json().catch(() => null)) as FirebaseVerifyBody | null;
  const idToken = String(body?.id_token ?? '').trim();
  if (!idToken) {
    throw Errors.badRequest('INVALID_REQUEST', 'Thiếu id_token Firebase');
  }
  const projectId = c.env.FIREBASE_PROJECT_ID;
  if (!projectId || projectId.startsWith('REPLACE_')) {
    // Misconfig rõ ràng — fail 500 với message rõ, không âm thầm fallback dev OTP.
    throw Errors.internal('FIREBASE_PROJECT_ID chưa cấu hình trên server');
  }
  const payload = await verifyFirebaseIdToken(idToken, {
    projectId,
    jwksUrl: c.env.FIREBASE_JWKS_URL || undefined,
  });
  const user = await upsertUserByPhone(c.env.DB, payload.phone);
  await setFirebaseUid(c.env.DB, user.id, payload.uid);
  const now = Math.floor(Date.now() / 1000);
  const token = await sign(
    { sub: user.id, role: user.role, phone: user.phone, exp: now + TOKEN_TTL_SECONDS },
    c.env.JWT_SECRET,
  );
  log('info', 'user_logged_in_firebase', { requestId: c.get('requestId'), userId: user.id });
  return c.json({ token, user: toPublicUser(user) });
});