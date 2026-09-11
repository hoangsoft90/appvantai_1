-- Phase 1 — Identity.
-- 1 tài xế = 1 xe (P0 không làm fleet management — plan §2.2, §11).
-- Bảng riêng cho profile tài xế để tách khỏi users (auth core).

CREATE TABLE IF NOT EXISTS driver_profiles (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL UNIQUE,
  vehicle_type      TEXT NOT NULL DEFAULT 'van',
  license_plate     TEXT NOT NULL DEFAULT '',
  capacity_kg       INTEGER NOT NULL DEFAULT 0,
  vehicle_length_cm INTEGER NOT NULL DEFAULT 0,
  vehicle_width_cm  INTEGER NOT NULL DEFAULT 0,
  vehicle_height_cm INTEGER NOT NULL DEFAULT 0,
  operating_area    TEXT NOT NULL DEFAULT '',
  status            TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'inactive')),
  created_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_driver_profiles_user_id ON driver_profiles (user_id);