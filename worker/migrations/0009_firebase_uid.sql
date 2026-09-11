-- Phase 7 §7.1 — Firebase Phone Auth: ghi nhận Firebase UID lần đầu login.
-- Lookup vẫn theo phone (SĐT là identity thật của app); firebase_uid chỉ là
-- telemetry/trace. UNIQUE nên 1 Firebase user không map 2 row users.
ALTER TABLE users ADD COLUMN firebase_uid TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_firebase_uid ON users (firebase_uid) WHERE firebase_uid IS NOT NULL;
