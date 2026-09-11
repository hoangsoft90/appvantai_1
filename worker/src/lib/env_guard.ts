import { Errors } from './errors';
import { log } from './logger';

/**
 * Production environment guard (plan2_final §7.1 + fix_p7_1.md #1).
 *
 * APP_ENV=production nhưng còn dev config → cấu hình nguy hiểm phải trở thành
 * lỗi runtime RÕ RÀNG (503 PRODUCTION_MISCONFIGURED), không chỉ log.
 *
 * Lưu ý nền tảng: Workers không thể "fail boot" — mọi isolate chạy cùng code,
 * chặn một isolate = chặn tất cả. Thay vào đó, MỌI request tới Worker cấu hình
 * sai nhận 503 kèm mã ổn định → sai cấu hình không thể bị bỏ qua.
 *
 * Dev không bị ảnh hưởng: placeholder JWT_SECRET hợp lệ CHỈ ở APP_ENV=dev.
 */
export function assertProductionEnv(env: {
  APP_ENV: string;
  ALLOW_DEV_OTP: string;
  JWT_SECRET: string;
  FIREBASE_PROJECT_ID?: string;
  FIREBASE_JWKS_URL?: string;
}): void {
  if (env.APP_ENV !== 'production') return;

  const problems: string[] = [];
  if (env.ALLOW_DEV_OTP === 'true') {
    problems.push('ALLOW_DEV_OTP=true — dev OTP phải tắt ở production (§7.2)');
  }
  if (!env.JWT_SECRET || env.JWT_SECRET === 'dev-secret-change-me-in-production') {
    problems.push('JWT_SECRET thiếu/vẫn là dev placeholder — dùng `wrangler secret put JWT_SECRET --env production`');
  }
  if (!env.FIREBASE_PROJECT_ID || env.FIREBASE_PROJECT_ID.startsWith('REPLACE_')) {
    problems.push('FIREBASE_PROJECT_ID chưa cấu hình — login Firebase sẽ 500 (§7.1)');
  }
  const jwks = env.FIREBASE_JWKS_URL;
  // fix_p7_1 #1: cửa hậu verify-bất-cứu-gì bị đóng — JWKS override chỉ còn
  // đường localhost (test/CI). Production luôn dùng JWKS công khai Google.
  if (jwks && !/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?/.test(jwks)) {
    problems.push('FIREBASE_JWKS_URL chỉ cho phép localhost (test) — production dùng JWKS công khai Google (§7.1)');
  }
  if (problems.length > 0) {
    log('error', 'PRODUCTION_ENV_GUARD', { problems });
    throw Errors.serviceUnavailable(
      'PRODUCTION_MISCONFIGURED',
      'Cấu hình máy chủ sai — liên hệ quản trị viên',
    );
  }
}
