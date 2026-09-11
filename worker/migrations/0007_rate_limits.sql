-- plan2_final §3.4 — Atomic rate limit trên D1 (KV GET/PUT KHÔNG atomic).
-- Mỗi key 1 row; UPSERT ... RETURNING count là 1 statement duy nhất → atomic.
CREATE TABLE IF NOT EXISTS rate_limits (
  key          TEXT PRIMARY KEY,
  window_start TEXT NOT NULL,
  count        INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_window ON rate_limits (window_start);
