import { Errors } from '../lib/errors';
import { getDriverProfile, type DriverProfile } from './profiles';
import { isBlockedEitherDirection } from './safety';
import { getUserById } from './users';

/**
 * Authorization helpers (plan2_final §1.1, §1.2, §1.5).
 * Mọi route/service dùng chung — không check role/quyền rời rạc từng nơi.
 * Backend là authority: role lấy từ auth middleware (DB), KHÔNG tin client.
 */

export type Role = 'driver' | 'customer' | 'admin';

/** Ném 403 nếu role hiện tại không nằm trong allowed (role từ DB qua auth middleware). */
export function requireRole(currentRole: string, ...allowed: Role[]): void {
  if (!(allowed as string[]).includes(currentRole)) {
    throw Errors.forbidden(
      'ROLE_FORBIDDEN',
      'Bạn không có quyền thực hiện thao tác này với vai trò hiện tại',
    );
  }
}

/**
 * Driver đủ điều kiện thao tác (contact/accept): phải có driver_profile active.
 * Lưu ý: profile tự tạo khi chọn role=driver có capacity_kg=0 — nơi cần
 * điều kiện xe thật (accept) phải kiểm tra thêm capacity/vehicle_type.
 */
export async function requireActiveDriverProfile(db: D1Database, driverId: string): Promise<DriverProfile> {
  const profile = await getDriverProfile(db, driverId);
  if (!profile || profile.status !== 'active') {
    throw Errors.forbidden(
      'DRIVER_PROFILE_INCOMPLETE',
      'Hồ sơ tài xế chưa hoàn thiện — vui lòng khai báo xe trước khi nhận hàng',
    );
  }
  return profile;
}

/**
 * Chặn giao dịch nếu 2 bên đã block nhau (bất kể chiều nào) — plan2_final §1.5:
 * block phải ảnh hưởng business operation (matching/contact/accept), không chỉ nằm ở DB.
 */
export async function requireNotBlockedEitherDirection(db: D1Database, a: string, b: string): Promise<void> {
  if (await isBlockedEitherDirection(db, a, b)) {
    throw Errors.forbidden('USER_BLOCKED', 'Bạn không thể giao dịch với người dùng này');
  }
}

/**
 * Legal consent enforce SERVER-SIDE (plan2_final §1.4): client checkbox chỉ là UX,
 * không phải security boundary. Mọi action cần consent (tạo đơn, contact, accept)
 * phải qua đây — server đọc DB, không tin client.
 */
export async function requireLegalConsent(db: D1Database, userId: string): Promise<void> {
  const user = await getUserById(db, userId);
  if (!user?.legal_consent_at) {
    throw Errors.forbidden(
      'LEGAL_CONSENT_REQUIRED',
      'Bạn cần đồng ý điều khoản sử dụng trước khi thực hiện thao tác này',
    );
  }
}
