#!/bin/bash
# =============================================================================
# Phase 6 — Pilot: seed corridor HN→HP (plan §28) + chạy matching + in metrics.
#
# Cách dùng:
#   bash scripts/seed_pilot.sh          # tự start wrangler dev (mock), seed, dừng server
#   npm run seed:pilot                  # tương đương
#   BASE=http://localhost:8787 bash scripts/seed_pilot.sh   # seed vào server đang chạy
#
# IDEMPOTENT: mỗi lần chạy, data seed CŨ (đơn notes='pilot' + trip của tài xế
# seed) bị xóa trước rồi tạo lại — chạy nhiều lần không nhân đôi. KHÔNG đụng
# data user thật (chỉ đụng phone seed 0983xxxxxx + đơn notes='pilot').
# --reset-seed: xóa data seed rồi thoát (không tạo lại).
#
# Tạo: 4 tài xế (xe khác nhau) + 8 đơn hàng dọc corridor (6 hợp lệ + 2 nhiễu
# ngoài corridor để kiểm tra pre-filter), 1 trip HN→HP mỗi tài xế, chạy
# matching, in match rate. Kết quả lưu bảng matches (funnel §29).
# =============================================================================
set -u
BASE="${BASE:-http://localhost:8787}"
CORRIDOR="${CORRIDOR:-hn_hp}"   # hoặc đổi script cho corridor khác
RESET_ONLY=0
[ "${1:-}" = "--reset-seed" ] && RESET_ONLY=1

# --- Tự quản lý server local (khi BASE không được override từ ngoài) ---
MANAGE_SERVER=0
if [ "$BASE" = "http://localhost:8787" ]; then
  MANAGE_SERVER=1
  cd "$(dirname "$0")/.."   # worker/
  pkill -f "worker[d]" 2>/dev/null || true
  sleep 2
  npx wrangler d1 migrations apply appvantai --local > /dev/null 2>&1 || true
  (npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock --var ALLOW_DEV_OTP:true --var APP_ENV:dev > /tmp/pilot_seed_wrangler.log 2>&1 &)
  for i in $(seq 1 30); do
    curl -s -o /dev/null "$BASE/health" && break
    sleep 1
  done
  if strings /tmp/pilot_seed_wrangler.log | grep -q "Address already in use"; then
    echo "✗ LỖI: port 8787 bị chiếm — dừng server cũ trước khi chạy seed" >&2
    exit 1
  fi
  curl -s -o /dev/null "$BASE/health" || { echo "✗ LỖI: wrangler dev không start được (xem /tmp/pilot_seed_wrangler.log)" >&2; exit 1; }
fi

cleanup() {
  [ "$MANAGE_SERVER" = "1" ] && pkill -f "worker[d]" 2>/dev/null || true
}
trap cleanup EXIT

fail() { echo "✗ LỖI: $*" >&2; exit 1; }

# Tọa độ corridor HN→HP (plan §28)
HN_LAT=21.0285; HN_LNG=105.8542
HY_LAT=20.646;  HY_LNG=106.051
HD_LAT=20.941;  HD_LNG=106.311
HP_LAT=20.8449; HP_LNG=106.6881

# Khung giờ lấy hàng: DYNAMIC (tính từ lúc chạy seed) — seed không bao giờ
# tạo đơn hết hạn. pickup_from = +2h, pickup_to = +12h (cùng = expires_at).
PF=$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)
PT=$(date -u -d '+12 hours' +%Y-%m-%dT%H:%M:%SZ)

# login phone role name → in token, và set role+name qua PATCH /me (đúng flow onboarding).
# LƯU Ý (bug cũ): user mới mặc định role=customer; nếu không PATCH /me set role=driver
# thì POST /trips trả 403 FORBIDDEN → matching không bao giờ chạy ("0 match").
login() { # phone role name
  local PHONE=$1 ROLE=$2 NAME=$3
  local OTP=$(curl -s -X POST $BASE/auth/request-otp -H 'Content-Type: application/json' -d "{\"phone\":\"$PHONE\"}" | jq -r '.dev_otp')
  [ -n "$OTP" ] && [ "$OTP" != "null" ] || fail "request-otp cho $PHONE thất bại"
  local TOKEN=$(curl -s -X POST $BASE/auth/verify-otp -H 'Content-Type: application/json' -d "{\"phone\":\"$PHONE\",\"otp\":\"$OTP\"}" | jq -r '.token')
  [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || fail "verify-otp cho $PHONE thất bại"
  # Re-submit cùng role là idempotent (plan3 Mục 1) — chạy lại seed không lỗi ROLE_LOCKED
  curl -s -X PATCH $BASE/me -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    -d "{\"name\":\"$NAME\",\"role\":\"$ROLE\"}" > /dev/null
  # Legal disclaimer (plan §18): bắt buộc trước khi tạo đơn / nhận đơn
  curl -s -X POST $BASE/me/legal-consent -H "Authorization: Bearer $TOKEN" > /dev/null
  echo "$TOKEN"
}

reset_seed_data() {
  # Xóa đúng data seed cũ (không đụng user thật):
  #  - matches của trip seed → contacts của đơn seed → đơn seed (notes='pilot')
  #  → trip của tài xế seed (phone 0983xx) → GPS KV key không ở D1 (tự hết hạn TTL).
  npx wrangler d1 execute appvantai --local --command "
    DELETE FROM matches WHERE trip_id IN (SELECT t.id FROM trips t JOIN users u ON u.id = t.driver_id WHERE u.phone LIKE '0983%');
    DELETE FROM trips WHERE driver_id IN (SELECT id FROM users WHERE phone LIKE '0983%');
    DELETE FROM contacts WHERE order_id IN (SELECT id FROM cargo_orders WHERE notes = 'pilot');
    DELETE FROM matches WHERE order_id IN (SELECT id FROM cargo_orders WHERE notes = 'pilot');
    DELETE FROM cargo_orders WHERE notes = 'pilot';" > /dev/null 2>&1 || true
}

echo "== Seed corridor $CORRIDOR (HN → Hưng Yên → Hải Dương → HP) =="
echo "   Khung giờ lấy hàng: $PF → $PT (UTC)"

if [ "$MANAGE_SERVER" = "1" ]; then
  echo "-- 0. Reset data seed cũ (idempotent) --"
  reset_seed_data
else
  # BASE trỏ server ngoài: vẫn thử reset (yêu cầu wrangler d1 local cùng project)
  cd "$(dirname "$0")/.."
  echo "-- 0. Reset data seed cũ (idempotent) --"
  reset_seed_data
fi

if [ "$RESET_ONLY" = "1" ]; then
  echo "Đã reset data seed (--reset-seed). Không tạo lại."
  exit 0
fi

echo "-- 1. Tài xế (4 loại xe khác nhau) --"
declare -A DRIVER_TOKEN
i=1
for entry in "truck 5000" "truck 8000" "van 1500" "pickup 1200"; do
  set -- $entry
  VEH=$1; CAP=$2
  PHONE="0983$(printf '%06d' $((500000 + i)))"
  T=$(login "$PHONE" driver "Tài Xế Pilot $i")
  DRIVER_TOKEN[$i]=$T
  curl -s -X PATCH $BASE/me/vehicle -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
    -d "{\"vehicle_type\":\"$VEH\",\"license_plate\":\"29C-${i}0$i\",\"capacity_kg\":$CAP,\"vehicle_length_cm\":700,\"vehicle_width_cm\":220,\"vehicle_height_cm\":200,\"operating_area\":\"HN-HP\"}" > /dev/null
  echo "  driver$i: $VEH $CAP kg ($PHONE)"
  i=$((i+1))
done

echo "-- 2. Chủ hàng + 8 đơn dọc corridor --"
declare -A ORDER_ID
j=1
create_order() { # lat lng addr label dlat dlng daddr weight veh price
  local PHONE="0983$(printf '%06d' $((600000 + j)))"
  local CUS=$(login "$PHONE" customer "Chủ Hàng Pilot $j")
  local O=$(curl -s -X POST $BASE/orders -H "Authorization: Bearer $CUS" -H 'Content-Type: application/json' \
    -d "{\"pickup_lat\":$1,\"pickup_lng\":$2,\"pickup_address\":\"$3\",\"delivery_lat\":$4,\"delivery_lng\":$5,\"delivery_address\":\"$6\",\"cargo_type\":\"general\",\"weight_kg\":$7,\"length_cm\":200,\"width_cm\":150,\"height_cm\":120,\"vehicle_requirement\":\"$8\",\"pickup_from\":\"$PF\",\"pickup_to\":\"$PT\",\"price\":$9,\"notes\":\"pilot\"}")
  local OID=$(echo "$O" | jq -r '.order.id')
  [ -n "$OID" ] && [ "$OID" != "null" ] || fail "tạo order$j thất bại: $(echo "$O" | jq -c '.error // .')"
  ORDER_ID[$j]=$OID
  echo "  order$j: $3 → $6 ($7 kg, $8, ${9}đ)"
  j=$((j+1))
}

# 6 đơn TRÊN corridor (match tốt kỳ vọng)
create_order $HN_LAT $HN_LNG "Hà Nội" $HP_LAT $HP_LNG "Hải Phòng" 500 truck 1500000      # 1: xuyên corridor
create_order $HN_LAT $HN_LNG "Hà Nội" $HD_LAT $HD_LNG "Hải Dương" 300 any 800000         # 2: nửa đường
create_order $HY_LAT $HY_LNG "Hưng Yên" $HP_LAT $HP_LNG "Hải Phòng" 1000 truck 1800000    # 3: giữa corridor
create_order $HD_LAT $HD_LNG "Hải Dương" $HP_LAT $HP_LNG "Hải Phòng" 400 truck 900000     # 4: cuối corridor
create_order $HN_LAT $HN_LNG "Hà Nội" $HY_LAT $HY_LNG "Hưng Yên" 200 pickup 500000        # 5: đầu corridor (xe pickup)
create_order $HY_LAT $HY_LNG "Hưng Yên" $HD_LAT $HD_LNG "Hải Dương" 800 van 700000        # 6: van phù hợp

# 2 đơn NHIỄU ngoài corridor (không được match — test grid pre-filter)
create_order 21.4 107.8 "Quảng Ninh" 21.4 107.8 "Quảng Ninh" 900 truck 1200000            # 7: ngoài corridor
create_order 20.3 105.6 "Thanh Hóa" 20.2 105.5 "Thanh Hóa" 300 truck 600000               # 8: ngược hướng

echo "-- 3. Trip mỗi tài xế + chạy matching --"
MATCH_TOTAL=0
MATCH_DRIVERS=0
for i in 1 2 3 4; do
  T=${DRIVER_TOKEN[$i]}
  TRIP=$(curl -s -X POST $BASE/trips -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
    -d "{\"from_lat\":$HN_LAT,\"from_lng\":$HN_LNG,\"from_address\":\"Hà Nội\",\"to_lat\":$HP_LAT,\"to_lng\":$HP_LNG,\"to_address\":\"Hải Phòng\"}")
  TRIP_ID=$(echo "$TRIP" | jq -r '.data.id')
  [ -n "$TRIP_ID" ] && [ "$TRIP_ID" != "null" ] || fail "tạo trip driver$i thất bại: $(echo "$TRIP" | jq -c '.error // .')"
  M=$(curl -s -X POST $BASE/trips/$TRIP_ID/matches -H "Authorization: Bearer $T")
  N=$(echo "$M" | jq -r '.data | length')
  [ "$N" != "null" ] || fail "matches driver$i trả lỗi: $(echo "$M" | jq -c '.error // .')"
  MATCH_TOTAL=$((MATCH_TOTAL + N))
  [ "$N" -gt 0 ] 2>/dev/null && MATCH_DRIVERS=$((MATCH_DRIVERS + 1))
  echo "  driver$i: $N match $(echo "$M" | jq -r '[.data[].score] | if length==0 then "(không có)" else join(",") end')"
done

echo ""
echo "=== PILOT METRICS (corridor $CORRIDOR) ==="
echo "Tài xế có ≥1 match: $MATCH_DRIVERS/4"
echo "Tổng match hiển thị: $MATCH_TOTAL"
echo ""
echo "Ghi chú: kết quả đã lưu bảng matches. Funnel tiếp theo (contact → accept →"
echo "completed) xem scripts/pilot_metrics.sql. Smoke test 1 vòng đầy đủ:"
echo "bash scripts/pilot_smoke.sh"
