-- Phase 3 — Maps + Matching (plan §11).
-- trips: chuyến của tài xế (origin → destination + polyline đã route).
-- route_cache: cache route OSRM (tránh gọi API lặp, plan §14).
-- matches: kết quả matching cho funnel metrics + explainability (§29).

CREATE TABLE IF NOT EXISTS trips (
  id                   TEXT PRIMARY KEY,
  driver_id            TEXT NOT NULL,
  origin_lat           REAL NOT NULL,
  origin_lng           REAL NOT NULL,
  origin_address       TEXT NOT NULL DEFAULT '',
  destination_lat      REAL NOT NULL,
  destination_lng      REAL NOT NULL,
  destination_address  TEXT NOT NULL DEFAULT '',
  route_polyline       TEXT NOT NULL DEFAULT '',  -- encoded polyline6
  distance_m           INTEGER NOT NULL DEFAULT 0,
  duration_s           INTEGER NOT NULL DEFAULT 0,
  direction            TEXT NOT NULL DEFAULT 'one_way'
                       CHECK (direction IN ('one_way', 'return')),
  status               TEXT NOT NULL DEFAULT 'planned'
                       CHECK (status IN ('planned', 'active', 'ended', 'cancelled')),
  started_at           TEXT,
  ended_at             TEXT,
  created_at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_trips_driver_status ON trips (driver_id, status);

CREATE TABLE IF NOT EXISTS route_cache (
  origin_key      TEXT NOT NULL,       -- "lat,lng" đã làm tròn ~11m
  destination_key TEXT NOT NULL,
  provider        TEXT NOT NULL DEFAULT 'osrm',
  polyline        TEXT NOT NULL,       -- encoded polyline6
  distance_m      INTEGER NOT NULL,
  duration_s      INTEGER NOT NULL,
  expires_at      TEXT NOT NULL,
  created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (origin_key, destination_key)
);

CREATE TABLE IF NOT EXISTS matches (
  id              TEXT PRIMARY KEY,
  trip_id         TEXT NOT NULL,
  order_id        TEXT NOT NULL,
  score           INTEGER NOT NULL,
  distance_score  INTEGER NOT NULL DEFAULT 0,
  route_score     INTEGER NOT NULL DEFAULT 0,
  direction_score INTEGER NOT NULL DEFAULT 0,
  vehicle_score   INTEGER NOT NULL DEFAULT 0,
  capacity_score  INTEGER NOT NULL DEFAULT 0,
  time_score      INTEGER NOT NULL DEFAULT 0,
  detour_km       REAL,
  reasons_json    TEXT NOT NULL DEFAULT '[]',
  created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_matches_trip_score ON matches (trip_id, score);