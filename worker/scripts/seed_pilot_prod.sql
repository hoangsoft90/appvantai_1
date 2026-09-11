-- =============================================================================
-- Seed PRODUCTION (D1 remote) — pilot corridor HN→HP + tài khoản admin.
--
-- Khác seed_pilot.sh (local, login qua dev OTP): file này chỉ INSERT/UPDATE SQL
-- qua `wrangler d1 execute --remote` — production không có dev OTP nên KHÔNG
-- login được bằng token seed. User SQL-only = an toàn hơn: token của họ chưa
-- từng tồn tại; user "sống" khi chủ số thật login Firebase (upsert
-- /auth/firebase KHÔNG ghi đè role — đã verify users.ts).
--
-- Idempotent: DELETE đúng data seed cũ trước (phone 0983*, notes='pilot') rồi
-- insert lại. KHÔNG đụng data user thật.
--
-- Chạy: wrangler d1 execute appvantai --remote --file scripts/seed_pilot_prod.sql
-- =============================================================================

-- 0) Dọn data seed cũ (idempotent — đúng thứ tự phụ thuộc)
DELETE FROM matches WHERE trip_id IN (SELECT t.id FROM trips t JOIN users u ON u.id = t.driver_id WHERE u.phone LIKE '0983%');
DELETE FROM trips WHERE driver_id IN (SELECT id FROM users WHERE phone LIKE '0983%');
DELETE FROM contacts WHERE order_id IN (SELECT id FROM cargo_orders WHERE notes = 'pilot');
DELETE FROM matches WHERE order_id IN (SELECT id FROM cargo_orders WHERE notes = 'pilot');
DELETE FROM cargo_orders WHERE notes = 'pilot';
DELETE FROM driver_profiles WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '0983%');
DELETE FROM users WHERE phone LIKE '0983%';

-- 1) Tài khoản admin (login Firebase lần đầu sẽ NHẬN LẠI role này — upsert giữ role)
INSERT INTO users (id, name, phone, role, status, legal_consent_at)
VALUES ('seed-admin-0000-0000-000000000001', 'Admin', '0363930250', 'admin', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
ON CONFLICT(phone) DO UPDATE SET role = 'admin', updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now');

-- 2) 4 tài xế seed + 8 chủ hàng seed (SQL-only, đúng tên/số như seed_pilot.sh)
INSERT INTO users (id, name, phone, role, status, legal_consent_at) VALUES
  ('seed-driver-0000-0000-000000000001', 'Tài Xế Pilot 1', '0983500001', 'driver', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  ('seed-driver-0000-0000-000000000002', 'Tài Xế Pilot 2', '0983500002', 'driver', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  ('seed-driver-0000-0000-000000000003', 'Tài Xế Pilot 3', '0983500003', 'driver', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  ('seed-driver-0000-0000-000000000004', 'Tài Xế Pilot 4', '0983500004', 'driver', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));

INSERT INTO driver_profiles (id, user_id, vehicle_type, license_plate, capacity_kg, vehicle_length_cm, vehicle_width_cm, vehicle_height_cm, operating_area) VALUES
  ('seed-dprof-0000-0000-000000000001', 'seed-driver-0000-0000-000000000001', 'truck',  '29C-101', 5000, 700, 220, 200, 'HN-HP'),
  ('seed-dprof-0000-0000-000000000002', 'seed-driver-0000-0000-000000000002', 'truck',  '29C-202', 8000, 700, 220, 200, 'HN-HP'),
  ('seed-dprof-0000-0000-000000000003', 'seed-driver-0000-0000-000000000003', 'van',    '29C-303', 1500, 700, 220, 200, 'HN-HP'),
  ('seed-dprof-0000-0000-000000000004', 'seed-driver-0000-0000-000000000004', 'pickup', '29C-404', 1200, 700, 220, 200, 'HN-HP');

INSERT INTO users (id, name, phone, role, status, legal_consent_at) VALUES
  ('seed-customer-0000-0000-000000000001', 'Chủ Hàng Pilot 1', '0983600001', 'customer', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  ('seed-customer-0000-0000-000000000002', 'Chủ Hàng Pilot 2', '0983600002', 'customer', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  ('seed-customer-0000-0000-000000000003', 'Chủ Hàng Pilot 3', '0983600003', 'customer', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  ('seed-customer-0000-0000-000000000004', 'Chủ Hàng Pilot 4', '0983600004', 'customer', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  ('seed-customer-0000-0000-000000000005', 'Chủ Hàng Pilot 5', '0983600005', 'customer', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  ('seed-customer-0000-0000-000000000006', 'Chủ Hàng Pilot 6', '0983600006', 'customer', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  ('seed-customer-0000-0000-000000000007', 'Chủ Hàng Pilot 7', '0983600007', 'customer', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  ('seed-customer-0000-0000-000000000008', 'Chủ Hàng Pilot 8', '0983600008', 'customer', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));

-- 3) 8 đơn pilot (6 trên corridor + 2 nhiễu ngoài corridor để test pre-filter)
--    pickup_from/to = +2h/+12h lúc chạy seed → không bao giờ hết hạn lúc seed;
--    expires_at = pickup_to (khớp hành vi API: đơn hết hạn cùng khung lấy hàng);
--    grid = FLOOR(lat|lng / 0.05) — khớp gridCell() trong orders.ts.
--    Cú pháp SQLite thuần: 8 INSERT riêng (VALUES của SQLite không đặt tên cột).

INSERT INTO cargo_orders (
  id, customer_id, pickup_lat, pickup_lng, pickup_address,
  delivery_lat, delivery_lng, delivery_address,
  cargo_type, weight_kg, length_cm, width_cm, height_cm,
  vehicle_requirement, pickup_from, pickup_to, price, notes,
  status, grid_lat, grid_lng, expires_at
) VALUES (
  'seed-order-0000-0000-000000000001', 'seed-customer-0000-0000-000000000001',
  21.0285, 105.8542, 'Hà Nội', 20.8449, 106.6881, 'Hải Phòng',
  'general', 500, 200, 150, 120, 'truck',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+2 hours'),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours'),
  1500000, 'pilot', 'posted',
  CAST(FLOOR(21.0285 / 0.05) AS INTEGER), CAST(FLOOR(105.8542 / 0.05) AS INTEGER),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours')
);

INSERT INTO cargo_orders (
  id, customer_id, pickup_lat, pickup_lng, pickup_address,
  delivery_lat, delivery_lng, delivery_address,
  cargo_type, weight_kg, length_cm, width_cm, height_cm,
  vehicle_requirement, pickup_from, pickup_to, price, notes,
  status, grid_lat, grid_lng, expires_at
) VALUES (
  'seed-order-0000-0000-000000000002', 'seed-customer-0000-0000-000000000002',
  21.0285, 105.8542, 'Hà Nội', 20.9410, 106.3110, 'Hải Dương',
  'general', 300, 200, 150, 120, 'any',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+2 hours'),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours'),
  800000, 'pilot', 'posted',
  CAST(FLOOR(21.0285 / 0.05) AS INTEGER), CAST(FLOOR(105.8542 / 0.05) AS INTEGER),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours')
);

INSERT INTO cargo_orders (
  id, customer_id, pickup_lat, pickup_lng, pickup_address,
  delivery_lat, delivery_lng, delivery_address,
  cargo_type, weight_kg, length_cm, width_cm, height_cm,
  vehicle_requirement, pickup_from, pickup_to, price, notes,
  status, grid_lat, grid_lng, expires_at
) VALUES (
  'seed-order-0000-0000-000000000003', 'seed-customer-0000-0000-000000000003',
  20.6460, 106.0510, 'Hưng Yên', 20.8449, 106.6881, 'Hải Phòng',
  'general', 1000, 200, 150, 120, 'truck',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+2 hours'),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours'),
  1800000, 'pilot', 'posted',
  CAST(FLOOR(20.6460 / 0.05) AS INTEGER), CAST(FLOOR(106.0510 / 0.05) AS INTEGER),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours')
);

INSERT INTO cargo_orders (
  id, customer_id, pickup_lat, pickup_lng, pickup_address,
  delivery_lat, delivery_lng, delivery_address,
  cargo_type, weight_kg, length_cm, width_cm, height_cm,
  vehicle_requirement, pickup_from, pickup_to, price, notes,
  status, grid_lat, grid_lng, expires_at
) VALUES (
  'seed-order-0000-0000-000000000004', 'seed-customer-0000-0000-000000000004',
  20.9410, 106.3110, 'Hải Dương', 20.8449, 106.6881, 'Hải Phòng',
  'general', 400, 200, 150, 120, 'truck',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+2 hours'),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours'),
  900000, 'pilot', 'posted',
  CAST(FLOOR(20.9410 / 0.05) AS INTEGER), CAST(FLOOR(106.3110 / 0.05) AS INTEGER),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours')
);

INSERT INTO cargo_orders (
  id, customer_id, pickup_lat, pickup_lng, pickup_address,
  delivery_lat, delivery_lng, delivery_address,
  cargo_type, weight_kg, length_cm, width_cm, height_cm,
  vehicle_requirement, pickup_from, pickup_to, price, notes,
  status, grid_lat, grid_lng, expires_at
) VALUES (
  'seed-order-0000-0000-000000000005', 'seed-customer-0000-0000-000000000005',
  21.0285, 105.8542, 'Hà Nội', 20.6460, 106.0510, 'Hưng Yên',
  'general', 200, 200, 150, 120, 'pickup',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+2 hours'),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours'),
  500000, 'pilot', 'posted',
  CAST(FLOOR(21.0285 / 0.05) AS INTEGER), CAST(FLOOR(105.8542 / 0.05) AS INTEGER),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours')
);

INSERT INTO cargo_orders (
  id, customer_id, pickup_lat, pickup_lng, pickup_address,
  delivery_lat, delivery_lng, delivery_address,
  cargo_type, weight_kg, length_cm, width_cm, height_cm,
  vehicle_requirement, pickup_from, pickup_to, price, notes,
  status, grid_lat, grid_lng, expires_at
) VALUES (
  'seed-order-0000-0000-000000000006', 'seed-customer-0000-0000-000000000006',
  20.6460, 106.0510, 'Hưng Yên', 20.9410, 106.3110, 'Hải Dương',
  'general', 800, 200, 150, 120, 'van',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+2 hours'),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours'),
  700000, 'pilot', 'posted',
  CAST(FLOOR(20.6460 / 0.05) AS INTEGER), CAST(FLOOR(106.0510 / 0.05) AS INTEGER),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours')
);

-- 2 đơn NHIỄU ngoài corridor — KHÔNG được match (test grid pre-filter)
INSERT INTO cargo_orders (
  id, customer_id, pickup_lat, pickup_lng, pickup_address,
  delivery_lat, delivery_lng, delivery_address,
  cargo_type, weight_kg, length_cm, width_cm, height_cm,
  vehicle_requirement, pickup_from, pickup_to, price, notes,
  status, grid_lat, grid_lng, expires_at
) VALUES (
  'seed-order-0000-0000-000000000007', 'seed-customer-0000-0000-000000000007',
  21.4000, 107.8000, 'Quảng Ninh', 21.4000, 107.8000, 'Quảng Ninh',
  'general', 900, 200, 150, 120, 'truck',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+2 hours'),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours'),
  1200000, 'pilot', 'posted',
  CAST(FLOOR(21.4000 / 0.05) AS INTEGER), CAST(FLOOR(107.8000 / 0.05) AS INTEGER),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours')
);

INSERT INTO cargo_orders (
  id, customer_id, pickup_lat, pickup_lng, pickup_address,
  delivery_lat, delivery_lng, delivery_address,
  cargo_type, weight_kg, length_cm, width_cm, height_cm,
  vehicle_requirement, pickup_from, pickup_to, price, notes,
  status, grid_lat, grid_lng, expires_at
) VALUES (
  'seed-order-0000-0000-000000000008', 'seed-customer-0000-0000-000000000008',
  20.3000, 105.6000, 'Thanh Hóa', 20.2000, 105.5000, 'Thanh Hóa',
  'general', 300, 200, 150, 120, 'truck',
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+2 hours'),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours'),
  600000, 'pilot', 'posted',
  CAST(FLOOR(20.3000 / 0.05) AS INTEGER), CAST(FLOOR(105.6000 / 0.05) AS INTEGER),
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+12 hours')
);
