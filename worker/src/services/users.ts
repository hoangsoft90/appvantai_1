import { Errors } from '../lib/errors';

export type UserRole = 'driver' | 'customer' | 'admin';
export type UserStatus = 'active' | 'suspended' | 'banned';

export interface User {
  id: string;
  name: string;
  phone: string;
  role: UserRole;
  status: UserStatus;
  legal_consent_at: string | null;
  /** Phase 7 — Firebase UID lần đầu login Firebase (null nếu login OTP dev) */
  firebase_uid?: string | null;
  created_at: string;
  updated_at: string;
}

export type PublicUser = Pick<User, 'id' | 'name' | 'phone' | 'role' | 'status'>;

/** Chuyển row DB thành user công khai (không expose dữ liệu nhạy cảm — plan §18). */
export function toPublicUser(u: User): PublicUser {
  return { id: u.id, name: u.name, phone: u.phone, role: u.role, status: u.status };
}

/**
 * Upsert user theo số điện thoại. User mới mặc định role='customer' —
 * Phase 1 (Identity) sẽ cho chọn driver/customer khi tạo profile.
 */
export async function upsertUserByPhone(db: D1Database, phone: string): Promise<User> {
  const id = crypto.randomUUID();
  await db
    .prepare(
      `INSERT INTO users (id, name, phone, role, status)
       VALUES (?, '', ?, 'customer', 'active')
       ON CONFLICT(phone) DO UPDATE SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
    )
    .bind(id, phone)
    .run();
  const row = await db
    .prepare(`SELECT id, name, phone, role, status, legal_consent_at, firebase_uid, created_at, updated_at FROM users WHERE phone = ?`)
    .bind(phone)
    .first<User>();
  if (!row) {
    throw Errors.internal('Không thể tạo tài khoản');
  }
  return row;
}

/**
 * Phase 7 §7.1 — Ghi nhận firebase_uid lần đầu login Firebase (idempotent).
 * Identity chính là phone (firebase_uid chỉ telemetry) nên không tạo row mới,
 * không đổi role/state khi UID đổi (vd: user đăng nhập lại bằng Firebase khác).
 * Nếu uid đã gắn row KHÁC (user Firebase đổi SĐT rồi login lại) → NULL ở row cũ:
 * login mới nhất thắng — tránh UNIQUE constraint 500.
 */
export async function setFirebaseUid(db: D1Database, userId: string, firebaseUid: string): Promise<void> {
  await db.batch([
    // Login mới nhất thắng: NULL hoá uid ở row cũ (nếu có) rồi gắn vào row hiện tại
    db.prepare(`UPDATE users SET firebase_uid = NULL, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE firebase_uid = ?2 AND id != ?1`).bind(userId, firebaseUid),
    db.prepare(`UPDATE users SET firebase_uid = ?2, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?1 AND firebase_uid IS NOT ?2`).bind(userId, firebaseUid),
  ]);
}

export async function getUserById(db: D1Database, id: string): Promise<User | null> {
  const row = await db
    .prepare(`SELECT id, name, phone, role, status, legal_consent_at, created_at, updated_at FROM users WHERE id = ?`)
    .bind(id)
    .first<User>();
  return row ?? null;
}

/** Cập nhật name/role (Phase 1 — Identity). Trả user mới hoặc null nếu không tồn tại. */
export async function updateUser(
  db: D1Database,
  id: string,
  patch: { name?: string; role?: UserRole },
): Promise<User | null> {
  const sets: string[] = [];
  const binds: unknown[] = [];
  if (patch.name !== undefined) {
    sets.push('name = ?');
    binds.push(patch.name);
  }
  if (patch.role !== undefined) {
    sets.push('role = ?');
    binds.push(patch.role);
  }
  if (sets.length === 0) return getUserById(db, id);
  sets.push("updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')");
  binds.push(id);
  await db.prepare(`UPDATE users SET ${sets.join(', ')} WHERE id = ?`).bind(...binds).run();
  return getUserById(db, id);
}