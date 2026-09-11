-- plan2_final §2 — Order lifecycle timestamps.
-- Giúp verify "correct timestamps" ở mỗi bước lifecycle (§13) + funnel metrics.
ALTER TABLE cargo_orders ADD COLUMN accepted_at TEXT;
ALTER TABLE cargo_orders ADD COLUMN pickup_at TEXT;
ALTER TABLE cargo_orders ADD COLUMN in_transit_at TEXT;
ALTER TABLE cargo_orders ADD COLUMN delivered_at TEXT;
ALTER TABLE cargo_orders ADD COLUMN completed_at TEXT;
ALTER TABLE cargo_orders ADD COLUMN cancelled_at TEXT;
