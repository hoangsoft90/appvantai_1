-- Phase 0 — Foundation (auth skeleton).
-- Các bảng khác (driver_profiles, trips, cargo_orders, ...) sẽ được thêm
-- trong migration của từng phase tiếp theo (xem plan §11 Data Model).

CREATE TABLE IF NOT EXISTS users (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL DEFAULT '',
  phone      TEXT NOT NULL UNIQUE,
  role       TEXT NOT NULL DEFAULT 'customer'
             CHECK (role IN ('driver', 'customer', 'admin')),
  status     TEXT NOT NULL DEFAULT 'active'
             CHECK (status IN ('active', 'suspended', 'banned')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_users_phone ON users (phone);