import { Errors } from '../lib/errors';

/**
 * Driver profile / vehicle (Phase 1 — Identity).
 * P0: 1 tài xế = 1 xe → driver_profiles chứa luôn thông tin xe
 * (plan §11: driver_profiles có vehicle_type, license_plate, capacity, dims).
 * Phase 3 (matching) sẽ đọc capacity_kg + vehicle_type từ đây.
 */

export const VEHICLE_TYPES = ['van', 'pickup', 'truck', 'container'] as const;
export type VehicleType = (typeof VEHICLE_TYPES)[number];

export interface DriverProfile {
  id: string;
  user_id: string;
  vehicle_type: string;
  license_plate: string;
  capacity_kg: number;
  vehicle_length_cm: number;
  vehicle_width_cm: number;
  vehicle_height_cm: number;
  operating_area: string;
  status: string;
  created_at: string;
  updated_at: string;
}

export interface VehicleInput {
  vehicle_type: string;
  license_plate: string;
  capacity_kg: number;
  vehicle_length_cm: number;
  vehicle_width_cm: number;
  vehicle_height_cm: number;
  operating_area: string;
}

/** Validate body PATCH /me/vehicle. Trả value chuẩn hóa hoặc ném ApiError. */
export function validateVehicleInput(body: unknown): VehicleInput {
  const b = (body ?? {}) as Record<string, unknown>;
  const vehicle_type = String(b.vehicle_type ?? '');
  if (!VEHICLE_TYPES.includes(vehicle_type as VehicleType)) {
    throw Errors.badRequest(
      'INVALID_VEHICLE_TYPE',
      `Loại xe không hợp lệ (cho phép: ${VEHICLE_TYPES.join(', ')})`,
    );
  }
  const license_plate = String(b.license_plate ?? '').trim();
  if (!/^[A-Za-z0-9.\- ]{4,12}$/.test(license_plate)) {
    throw Errors.badRequest('INVALID_LICENSE_PLATE', 'Biển số xe không hợp lệ');
  }
  const intField = (v: unknown, field: string, max: number, label: string): number => {
    const n = Number(v);
    if (!Number.isFinite(n) || n < 0 || n > max || !Number.isInteger(n)) {
      throw Errors.badRequest('INVALID_FIELD', `${label} không hợp lệ`);
    }
    return n;
  };
  const capacity_kg = intField(b.capacity_kg, 'capacity_kg', 100_000, 'Tải trọng');
  const vehicle_length_cm = intField(b.vehicle_length_cm, 'vehicle_length_cm', 2_000, 'Chiều dài xe');
  const vehicle_width_cm = intField(b.vehicle_width_cm, 'vehicle_width_cm', 2_000, 'Chiều rộng xe');
  const vehicle_height_cm = intField(b.vehicle_height_cm, 'vehicle_height_cm', 2_000, 'Chiều cao xe');
  const operating_area = String(b.operating_area ?? '').trim().slice(0, 200);
  return {
    vehicle_type,
    license_plate,
    capacity_kg,
    vehicle_length_cm,
    vehicle_width_cm,
    vehicle_height_cm,
    operating_area,
  };
}

const PROFILE_COLS = `
  id, user_id, vehicle_type, license_plate, capacity_kg,
  vehicle_length_cm, vehicle_width_cm, vehicle_height_cm,
  operating_area, status, created_at, updated_at
`;

export async function getDriverProfile(db: D1Database, userId: string): Promise<DriverProfile | null> {
  const row = await db
    .prepare(`SELECT ${PROFILE_COLS} FROM driver_profiles WHERE user_id = ?`)
    .bind(userId)
    .first<DriverProfile>();
  return row ?? null;
}

/** Tạo profile rỗng khi user chọn vai trò driver (có thể sửa sau). */
export async function ensureDriverProfile(db: D1Database, userId: string): Promise<DriverProfile> {
  const existing = await getDriverProfile(db, userId);
  if (existing) return existing;
  const id = crypto.randomUUID();
  await db
    .prepare(
      `INSERT INTO driver_profiles (id, user_id) VALUES (?, ?)
       ON CONFLICT(user_id) DO NOTHING`,
    )
    .bind(id, userId)
    .run();
  const profile = await getDriverProfile(db, userId);
  if (!profile) {
    throw Errors.internal('Không thể tạo hồ sơ tài xế');
  }
  return profile;
}

export async function upsertDriverProfile(
  db: D1Database,
  userId: string,
  input: VehicleInput,
): Promise<DriverProfile> {
  const id = crypto.randomUUID();
  await db
    .prepare(
      `INSERT INTO driver_profiles (
         id, user_id, vehicle_type, license_plate, capacity_kg,
         vehicle_length_cm, vehicle_width_cm, vehicle_height_cm, operating_area
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET
         vehicle_type = excluded.vehicle_type,
         license_plate = excluded.license_plate,
         capacity_kg = excluded.capacity_kg,
         vehicle_length_cm = excluded.vehicle_length_cm,
         vehicle_width_cm = excluded.vehicle_width_cm,
         vehicle_height_cm = excluded.vehicle_height_cm,
         operating_area = excluded.operating_area,
         updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
    )
    .bind(
      id,
      userId,
      input.vehicle_type,
      input.license_plate,
      input.capacity_kg,
      input.vehicle_length_cm,
      input.vehicle_width_cm,
      input.vehicle_height_cm,
      input.operating_area,
    )
    .run();
  const profile = await getDriverProfile(db, userId);
  if (!profile) {
    throw Errors.internal('Không thể lưu thông tin xe');
  }
  return profile;
}