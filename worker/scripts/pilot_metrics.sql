-- Phase 6 — Pilot metrics (plan §29: funnel matching → contact → accept → done).
-- Chạy: npx wrangler d1 execute appvantai --local --file scripts/pilot_metrics.sql
--       (production: bỏ --local sau khi deploy)
-- LƯU Ý: local dev DB chứa residue E2E cũ (users/contacts/matches từ các suite
-- trước) → số liệu chỉ đúng khi chạy trên DB sạch (DB riêng cho pilot hoặc
-- --reset-seed + wipe trước khi mở pilot thật).

-- 1) Nguồn cung/cầu trên corridor (liquidity §29)
SELECT
  (SELECT COUNT(*) FROM users WHERE role='driver' AND status='active') AS active_drivers,
  (SELECT COUNT(*) FROM users WHERE role='customer' AND status='active') AS active_customers,
  (SELECT COUNT(*) FROM cargo_orders WHERE status IN ('posted','matched','contacted')) AS open_orders,
  (SELECT COUNT(*) FROM trips WHERE status IN ('planned','active')) AS active_trips;

-- 2) Funnel: match hiển thị → contact → accept (§29)
SELECT
  (SELECT COUNT(*) FROM matches) AS matches_shown,
  (SELECT COUNT(*) FROM contacts) AS contacts_made,
  (SELECT COUNT(*) FROM cargo_orders WHERE status='accepted' AND driver_id IS NOT NULL) AS accepts,
  (SELECT COUNT(*) FROM cargo_orders WHERE status IN ('completed','delivered')) AS completed,
  (SELECT COUNT(*) FROM cargo_orders WHERE status='cancelled') AS cancelled;

-- 3) Phân bố score của matches (kiểm tra matching quality §29)
SELECT
  CASE
    WHEN score >= 85 THEN '85-100 (excellent)'
    WHEN score >= 75 THEN '75-84 (good)'
    WHEN score >= 60 THEN '60-74 (possible)'
    ELSE '<60 (weak)'
  END AS score_band,
  COUNT(*) AS n
FROM matches
GROUP BY score_band
ORDER BY MIN(score) DESC;

-- 4) Lý do reject chính — heuristic từ score components thấp
--    (mỗi component <50% max ⇒ driver/customer có thể tinh chỉnh)
SELECT
  SUM(CASE WHEN distance_score < 10 THEN 1 ELSE 0 END) AS weak_distance,
  SUM(CASE WHEN route_score < 15 THEN 1 ELSE 0 END)    AS weak_route,
  SUM(CASE WHEN direction_score < 12 THEN 1 ELSE 0 END) AS weak_direction,
  SUM(CASE WHEN time_score < 5 THEN 1 ELSE 0 END)       AS weak_time,
  COUNT(*) AS total
FROM matches;