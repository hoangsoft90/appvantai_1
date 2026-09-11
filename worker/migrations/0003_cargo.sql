-- Phase 2 — Marketplace (cargo orders).
-- Grid Index (plan §12): grid_lat/grid_lng = FLOOR(pickup / 0.05) ~5.5km/ô,
-- giúp cheap pre-filter của matching (Phase 3) chỉ quét 9 ô lân cận.

CREATE TABLE IF NOT EXISTS cargo_orders (
  id                   TEXT PRIMARY KEY,
  customer_id          TEXT NOT NULL,
  pickup_lat           REAL NOT NULL,
  pickup_lng           REAL NOT NULL,
  pickup_address       TEXT NOT NULL DEFAULT '',
  delivery_lat         REAL NOT NULL,
  delivery_lng         REAL NOT NULL,
  delivery_address     TEXT NOT NULL DEFAULT '',
  cargo_type           TEXT NOT NULL DEFAULT 'general',
  weight_kg            INTEGER NOT NULL DEFAULT 0,
  length_cm            INTEGER NOT NULL DEFAULT 0,
  width_cm             INTEGER NOT NULL DEFAULT 0,
  height_cm            INTEGER NOT NULL DEFAULT 0,
  vehicle_requirement  TEXT NOT NULL DEFAULT 'any',
  pickup_from          TEXT NOT NULL,
  pickup_to            TEXT NOT NULL,
  price                INTEGER NOT NULL DEFAULT 0,
  notes                TEXT NOT NULL DEFAULT '',
  status               TEXT NOT NULL DEFAULT 'posted'
                       CHECK (status IN (
                         'posted', 'matched', 'contacted', 'accepted',
                         'pickup', 'in_transit', 'delivered', 'completed',
                         'cancelled', 'expired', 'rejected'
                       )),
  grid_lat             INTEGER NOT NULL DEFAULT 0,
  grid_lng             INTEGER NOT NULL DEFAULT 0,
  expires_at           TEXT NOT NULL,
  created_at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_cargo_orders_customer_id ON cargo_orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_cargo_orders_status ON cargo_orders (status);
CREATE INDEX IF NOT EXISTS idx_cargo_orders_expires_at ON cargo_orders (expires_at);
-- Grid Index (plan §12): cheap pre-filter cho matching
CREATE INDEX IF NOT EXISTS idx_cargo_orders_grid ON cargo_orders (grid_lat, grid_lng, status, expires_at);