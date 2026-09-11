-- Phase 5 — Safety/Admin (plan §11, §17, §18, §19).
-- contacts: ghi nhận liên hệ (CONTACTED) + rate limit contact (§19).
-- reports / blocks: trust layer (§18).
-- audit_logs: bằng chứng pháp lý (legal disclaimer tick §18) + admin moderation.
-- cargo_orders.driver_id: Atomic Accept (§10) — driver nhận đơn.
-- users.legal_consent_at: thời điểm user tick disclaimer (§18).

-- Atomic Accept: cột driver_id trên đơn (nullable tới khi có driver nhận).
ALTER TABLE cargo_orders ADD COLUMN driver_id TEXT;

CREATE INDEX IF NOT EXISTS idx_cargo_orders_driver_id ON cargo_orders (driver_id);

CREATE TABLE IF NOT EXISTS contacts (
  id            TEXT PRIMARY KEY,
  order_id      TEXT NOT NULL,
  driver_id     TEXT NOT NULL,
  customer_id   TEXT NOT NULL,
  contact_type  TEXT NOT NULL DEFAULT 'phone'
                CHECK (contact_type IN ('phone', 'call', 'zalo')),
  created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_contacts_order_id ON contacts (order_id);
CREATE INDEX IF NOT EXISTS idx_contacts_driver_id ON contacts (driver_id);

CREATE TABLE IF NOT EXISTS reports (
  id             TEXT PRIMARY KEY,
  reporter_id    TEXT NOT NULL,
  target_user_id TEXT NOT NULL,
  order_id       TEXT,
  reason         TEXT NOT NULL,
  description    TEXT NOT NULL DEFAULT '',
  status         TEXT NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_reports_status ON reports (status);
CREATE INDEX IF NOT EXISTS idx_reports_target ON reports (target_user_id);

CREATE TABLE IF NOT EXISTS blocks (
  id              TEXT PRIMARY KEY,
  user_id         TEXT NOT NULL,
  blocked_user_id TEXT NOT NULL,
  created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE (user_id, blocked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_user_id ON blocks (user_id);

-- Audit log: mọi hành động quan trọng (accept, contact, report, block,
-- admin action, legal consent) — plan §18 cần bằng chứng thời gian + IP.
CREATE TABLE IF NOT EXISTS audit_logs (
  id          TEXT PRIMARY KEY,
  actor_id    TEXT,
  entity_type TEXT NOT NULL,
  entity_id   TEXT,
  action      TEXT NOT NULL,
  metadata    TEXT NOT NULL DEFAULT '{}',
  ip          TEXT NOT NULL DEFAULT '',
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_logs (actor_id);

-- Legal disclaimer (§18): thời điểm tick + lưu audit_logs kèm IP.
ALTER TABLE users ADD COLUMN legal_consent_at TEXT;