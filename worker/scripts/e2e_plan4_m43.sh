#!/usr/bin/env bash
# =============================================================================
# plan4_final — E2E Mục 4.3: Match Card contract end-to-end
# API response PHẢI chứa đủ: score, pickup_km, detour_km, reasons, order
# (điểm lấy/giao, khối lượng, giá) — card UI đọc đúng các field này.
# Wipe data cũ trước (D1 cũ poison matching — trap đã biết).
# =============================================================================
set -u
cd "$(dirname "$0")/.."

BASE="http://localhost:8787"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1  -->  $2"; }
check() { if printf '%s' "$3" | grep -q "$2"; then ok "$1"; else fail "$1" "$3"; fi; }

TAG=$(date +%s)
C1="+8497${TAG: -5}11"
D1="+8497${TAG: -5}12"

pkill -f "worker[d]" 2>/dev/null || true
sleep 2
npx wrangler d1 migrations apply appvantai --local > /dev/null 2>&1 || true
# Wipe đơn/chuyến cũ (dữ liệu test cũ chiếm Top-5 rồi detour-reject → rỗng ảo)
npx wrangler d1 execute appvantai --local --command "DELETE FROM matches; DELETE FROM cargo_orders; DELETE FROM trips;" > /dev/null 2>&1 || true
(npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock --var ALLOW_DEV_OTP:true --var APP_ENV:dev > /tmp/p4_m43_wrangler.log 2>&1 &)
for i in $(seq 1 30); do curl -s -o /dev/null "$BASE/health" && break; sleep 1; done

jqget() { printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$2" 2>/dev/null; }

login() {
  local phone="$1" otp tok
  otp=$(jqget "$(curl -s -X POST "$BASE/auth/request-otp" -H 'content-type: application/json' -d "{\"phone\":\"$phone\"}")" "d.get('dev_otp','')")
  [ -z "$otp" ] && { echo ""; return; }
  for attempt in 1 2 3; do
    tok=$(jqget "$(curl -s -X POST "$BASE/auth/verify-otp" -H 'content-type: application/json' -d "{\"phone\":\"$phone\",\"otp\":\"$otp\"}")" "d.get('token','')")
    [ -n "$tok" ] && { echo "$tok"; return; }
    sleep 2
  done
  echo ""
}

TOK_C=$(login "$C1")
TOK_D=$(login "$D1")
[ -z "$TOK_C" ] || [ -z "$TOK_D" ] && { echo "FAIL: setup login"; exit 1; }

curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"name":"Chủ Hàng KCN"}' > /dev/null
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_C" > /dev/null
curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_D" -H 'content-type: application/json' -d '{"name":"Tài Xế Radar","role":"driver"}' > /dev/null
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_D" > /dev/null
# Driver PHẢI có xe — profile rỗng → capacity_kg=0 → filter loại mọi đơn (m43 nghèo match ảo)
curl -s -X PATCH "$BASE/me/vehicle" -H "Authorization: Bearer $TOK_D" -H 'content-type: application/json' \
  -d '{"vehicle_type":"van","license_plate":"29A-12345","capacity_kg":5000,"vehicle_length_cm":600,"vehicle_width_cm":220,"vehicle_height_cm":230}' > /dev/null

# Order: pickup/delivery TRÊN tuyến Bắc Giang → Bắc Ninh (mock OSRM), khung giờ rộng
ORDER=$(jqget "$(curl -s -X POST "$BASE/orders" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{
  "pickup_lat":21.02,"pickup_lng":105.83,"pickup_address":"Bắc Giang",
  "delivery_lat":20.98,"delivery_lng":105.82,"delivery_address":"Bắc Ninh",
  "cargo_type":"general","vehicle_requirement":"any","weight_kg":800,"price":1200000,
  "pickup_from":"2030-01-01T01:00:00Z","pickup_to":"2030-01-01T08:00:00Z"}')" "d.get('order',{}).get('id','')")

TRIP=$(jqget "$(curl -s -X POST "$BASE/trips" -H "Authorization: Bearer $TOK_D" -H 'content-type: application/json' -d '{
  "from_lat":21.03,"from_lng":105.84,"from_address":"Bắc Giang",
  "to_lat":21.00,"to_lng":105.83,"to_address":"Bắc Ninh","trip_type":"one_way"}')" "d.get('data',{}).get('id','')")

echo "=== MỤC 4.3: MATCH CARD CONTRACT END-TO-END ==="

R=$(curl -s -X POST "$BASE/trips/$TRIP/matches" -H "Authorization: Bearer $TOK_D")
COUNT=$(printf '%s' "$R" | python3 -c "import sys,json;print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null)
if [ "$COUNT" -ge 1 ] 2>/dev/null; then ok "4.3.1 radar tìm thấy match ($COUNT)"; else fail "4.3.1 radar tìm thấy match" "$R"; fi

M=$(printf '%s' "$R" | python3 -c "import sys,json;d=json.load(sys.stdin)['data'];print(json.dumps(d[0]))" 2>/dev/null)
check "4.3.2 có score" "\"score\":" "$M"
check "4.3.3 có pickup_km (cách tuyến)" "\"pickup_km\":" "$M"
check "4.3.4 có detour_km" "\"detour_km\":" "$M"
check "4.3.5 có reasons[]" "\"reasons\":" "$M"
check "4.3.6 order summary có điểm lấy/giao" "pickup_address" "$M"
check "4.3.7 order summary có khối lượng" "weight_kg" "$M"
check "4.3.8 order summary có giá" "price" "$M"
MATCH_ID=$(printf '%s' "$M" | python3 -c "import sys,json;print(json.load(sys.stdin)['order']['id'])" 2>/dev/null)
[ "$MATCH_ID" = "$ORDER" ] && ok "4.3.9 đơn đúng khớp vào match" || fail "4.3.9 đơn đúng khớp vào match" "$MATCH_ID != $ORDER"

VAL=$(printf '%s' "$M" | python3 -c "import sys,json;m=json.load(sys.stdin);print(m['pickup_km']>0 and m['detour_km'] is not None)" 2>/dev/null)
[ "$VAL" = "True" ] && ok "4.3.10 pickup_km > 0 và detour_km có giá trị thật (không 0 giả)" || fail "4.3.10 giá trị thật" "$M"

N=$(printf '%s' "$M" | python3 -c "import sys,json;print(len(json.load(sys.stdin)['reasons']))" 2>/dev/null)
[ "${N:-0}" -ge 3 ] 2>/dev/null && ok "4.3.11 reasons đủ giải thích ($N lý do)" || fail "4.3.11 reasons" "$M"

echo ""
echo "==================================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL GREEN" || echo "HAS FAILURES"
pkill -f "worker[d]" 2>/dev/null || true
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
