-- plan2_final §4.1 — Return Trip (core differentiator).
-- trip_type: 'one_way' (chạy A→B, nhận hàng cùng chiều) hoặc 'return'
-- (chạy A→B với xe rỗng chiều đi, tìm hàng B→A về).
ALTER TABLE trips ADD COLUMN trip_type TEXT NOT NULL DEFAULT 'one_way'
  CHECK (trip_type IN ('one_way', 'return'));
