#!/bin/bash
# =============================================================================
# Phase 6 — Smoke test 1 vòng lặp cốt lõi TRÊN DATA SEED (phase6_pilot §6.5):
#   match → contact (nhận SĐT) → accept → cancel-sau-accept BỊ CHẶN
#   → GPS planned-reject / active-OK / end-dừng → pickup → in-transit
#   → delivered → customer complete.
#
# Cách chạy:
#   npm run seed:pilot      # seed trước (1 lần)
#   npm run pilot:smoke     # hoặc: bash scripts/pilot_smoke.sh
#
# Chọn động 1 đơn seed còn 'posted' (khớp xe truck 5t của driver1) → chạy
# lại nhiều lần không cần re-seed (đơn đã dùng bị bỏ qua vì không còn posted).
# In PASS/FAIL từng bước + funnel counts cuối cùng.
# =============================================================================
set -u
BASE="${BASE:-http://localhost:8787}"

MANAGE_SERVER=0
if [ "$BASE" = "http://localhost:8787" ]; then
  MANAGE_SERVER=1
  cd "$(dirname "$0")/.."
  pkill -f "worker[d]" 2>/dev/null || true
  sleep 2
  npx wrangler d1 migrations apply appvantai --local > /dev/null 2>&1 || true
  (npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock --var ALLOW_DEV_OTP:true --var APP_ENV:dev > /tmp/pilot_smoke_wrangler.log 2>&1 &)
  for i in $(seq 1 30); do curl -s -o /dev/null "$BASE/health" && break; sleep 1; done
  if strings /tmp/pilot_smoke_wrangler.log | grep -q "Address already in use"; then
    echo "✗ LỖI: port 8787 bị chiếm — dừng server cũ trước khi chạy" >&2
    exit 1
  fi
  curl -s -o /dev/null "$BASE/health" || { echo "✗ LỖI: wrangler dev không start được" >&2; exit 1; }
fi
cleanup() { [ "$MANAGE_SERVER" = "1" ] && pkill -f "worker[d]" 2>/dev/null || true; }
trap cleanup EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1  -->  $2"; }
json() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }
body() { printf '%s' "$1" | jq -c '.error // .' 2>/dev/null; }

login() { # phone → token (user seed đã tồn tại, chỉ cần OTP)
  local OTP=$(curl -s -X POST $BASE/auth/request-otp -H 'Content-Type: application/json' -d "{\"phone\":\"$1\"}" | jq -r '.dev_otp')
  [ -n "$OTP" ] && [ "$OTP" != "null" ] || { echo ""; return; }
  curl -s -X POST $BASE/auth/verify-otp -H 'Content-Type: application/json' -d "{\"phone\":\"$1\",\"otp\":\"$OTP\"}" | jq -r '.token'
}

HN_LAT=21.0285; HN_LNG=105.8542
HP_LAT=20.8449; HP_LNG=106.6881

echo "== PILOT SMOKE — 1 vòng lặp match → contact → accept → lifecycle → complete =="

TOK_D=$(login "0983500001")   # driver1: truck 5000 kg
[ -n "$TOK_D" ] && [ "$TOK_D" != "null" ] || { echo "FAIL: login driver seed"; exit 1; }

# --- 1. Chọn động 1 đơn seed còn posted (khớp truck 5t, trong corridor) ---
FOUND=""
for j in 1 2 3 4 5 6 7 8; do
  TOK_C_J=$(login "098360000$j")
  [ -n "$TOK_C_J" ] && [ "$TOK_C_J" != "null" ] || continue
  PICK=$(curl -s "$BASE/orders" -H "Authorization: Bearer $TOK_C_J" | jq -r \
    '.orders[]? | select(.notes=="pilot" and .status=="posted"
        and .weight_kg <= 5000
        and (.vehicle_requirement=="any" or .vehicle_requirement=="truck")
        and (.pickup_address | test("Hà Nội|Hưng Yên|Hải Dương")))
      | .id' 2>/dev/null | head -1)
  if [ -n "$PICK" ] && [ "$PICK" != "null" ]; then
    ORDER_ID="$PICK"; TOK_C="$TOK_C_J"; FOUND=1; break
  fi
done
if [ -z "$FOUND" ]; then
  echo "✗ Không còn đơn seed 'posted' khớp — chạy lại: npm run seed:pilot" >&2
  exit 1
fi
echo "Đơn chọn: $ORDER_ID"

# --- 2. Match: trip HN→HP cho driver1, đơn phải xuất hiện trong radar ---
TRIP=$(curl -s -X POST "$BASE/trips" -H "Authorization: Bearer $TOK_D" -H 'Content-Type: application/json' \
  -d "{\"from_lat\":$HN_LAT,\"from_lng\":$HN_LNG,\"from_address\":\"Hà Nội\",\"to_lat\":$HP_LAT,\"to_lng\":$HP_LNG,\"to_address\":\"Hải Phòng\"}")
TRIP_ID=$(json "$TRIP" '.data.id')
[ -n "$TRIP_ID" ] && [ "$TRIP_ID" != "null" ] && ok "2.1 tạo trip HN→HP" || fail "2.1 tạo trip HN→HP" "$(body "$TRIP")"

MATCHES=$(curl -s -X POST "$BASE/trips/$TRIP_ID/matches" -H "Authorization: Bearer $TOK_D")
HIT=$(json "$MATCHES" "[.data[] | select(.order.id==\"$ORDER_ID\")][0]")
[ -n "$HIT" ] && [ "$HIT" != "null" ] && ok "2.2 radar thấy đơn seed (score=$(json "$HIT" '.score'), pickup_km=$(json "$HIT" '.pickup_km'))" || fail "2.2 radar thấy đơn seed" "$(body "$MATCHES")"
[ "$(json "$HIT" '.reasons | length')" -ge 3 ] 2>/dev/null && ok "2.3 match có reasons giải thích" || fail "2.3 reasons" "$HIT"

# --- 3. Contact: driver nhận SĐT chủ hàng ---
CONTACT=$(curl -s -X POST "$BASE/orders/$ORDER_ID/contact" -H "Authorization: Bearer $TOK_D")
CPHONE=$(json "$CONTACT" '.data.phone')
[ -n "$CPHONE" ] && [ "$CPHONE" != "null" ] && ok "3.1 contact trả SĐT chủ hàng ($CPHONE)" || fail "3.1 contact trả SĐT" "$(body "$CONTACT")"

# --- 4. Accept ---
ACC=$(curl -s -X POST "$BASE/orders/$ORDER_ID/accept" -H "Authorization: Bearer $TOK_D")
[ "$(json "$ACC" '.data.accepted')" = "true" ] && ok "4.1 accept thành công (atomic)" || fail "4.1 accept" "$(body "$ACC")"

# --- 5. Cancel sau accept PHẢI bị chặn (DoD phase 6) ---
CXL=$(curl -s -X POST "$BASE/orders/$ORDER_ID/cancel" -H "Authorization: Bearer $TOK_C")
CODE=$(json "$CXL" '.error.code')
[ "$CODE" = "CANCEL_NOT_ALLOWED" ] && ok "5.1 cancel sau accept bị chặn (409 CANCEL_NOT_ALLOWED)" || fail "5.1 cancel sau accept bị chặn" "$(body "$CXL")"

# --- 6. GPS: planned reject → start → gửi OK → end dừng ---
LOC_PLANNED=$(curl -s -X POST "$BASE/trips/$TRIP_ID/location" -H "Authorization: Bearer $TOK_D" -H 'Content-Type: application/json' -d '{"lat":21.0,"lng":105.85}')
[ "$(json "$LOC_PLANNED" '.error.code')" = "TRIP_NOT_ACTIVE" ] && ok "6.1 GPS khi planned bị chặn" || fail "6.1 GPS planned" "$(body "$LOC_PLANNED")"
START=$(curl -s -X POST "$BASE/trips/$TRIP_ID/start" -H "Authorization: Bearer $TOK_D")
[ "$(json "$START" '.data.status // .data.trip.status')" = "active" ] && ok "6.2 start trip → active" || fail "6.2 start trip" "$(body "$START")"
LOC_OK=$(curl -s -X POST "$BASE/trips/$TRIP_ID/location" -H "Authorization: Bearer $TOK_D" -H 'Content-Type: application/json' -d '{"lat":21.0,"lng":105.85}')
[ "$(json "$LOC_OK" '.data.ok // .data.throttled // .data.accepted // .data')" != "" ] && [ "$(json "$LOC_OK" '.error.code')" = "null" ] && ok "6.3 gửi GPS khi active OK" || fail "6.3 GPS active" "$(body "$LOC_OK")"
ENDT=$(curl -s -X POST "$BASE/trips/$TRIP_ID/end" -H "Authorization: Bearer $TOK_D")
[ "$(json "$ENDT" '.data.status // .data.trip.status')" = "ended" ] && ok "6.4 end trip → ended (dừng track)" || fail "6.4 end trip" "$(body "$ENDT")"

# --- 7. Lifecycle driver: pickup → in-transit → delivered ---
P=$(curl -s -X POST "$BASE/orders/$ORDER_ID/pickup" -H "Authorization: Bearer $TOK_D")
[ "$(json "$P" '.data.status')" = "pickup" ] && ok "7.1 pickup" || fail "7.1 pickup" "$(body "$P")"
T=$(curl -s -X POST "$BASE/orders/$ORDER_ID/in-transit" -H "Authorization: Bearer $TOK_D")
[ "$(json "$T" '.data.status')" = "in_transit" ] && ok "7.2 in-transit" || fail "7.2 in-transit" "$(body "$T")"
D=$(curl -s -X POST "$BASE/orders/$ORDER_ID/delivered" -H "Authorization: Bearer $TOK_D")
[ "$(json "$D" '.data.status')" = "delivered" ] && ok "7.3 delivered" || fail "7.3 delivered" "$(body "$D")"

# --- 8. Customer complete → completed ---
CP=$(curl -s -X POST "$BASE/orders/$ORDER_ID/complete" -H "Authorization: Bearer $TOK_C")
[ "$(json "$CP" '.data.status')" = "completed" ] && ok "8.1 customer complete → COMPLETED (hoàn tất vòng lặp)" || fail "8.1 complete" "$(body "$CP")"

echo ""
echo "=== FUNNEL SAU SMOKE (counts) ==="
cd "$(dirname "$0")/.." 2>/dev/null
npx wrangler d1 execute appvantai --local --command \
  "SELECT (SELECT COUNT(*) FROM matches) AS matches_shown, (SELECT COUNT(*) FROM contacts) AS contacts_made, (SELECT COUNT(*) FROM cargo_orders WHERE status='accepted') AS accepted_now, (SELECT COUNT(*) FROM cargo_orders WHERE status='completed') AS completed, (SELECT COUNT(*) FROM cargo_orders WHERE status='cancelled') AS cancelled" \
  2>/dev/null | grep -E '"(matches_shown|contacts_made|accepted_now|completed|cancelled)"'

echo ""
echo "==================================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "SMOKE ALL GREEN ✅" || echo "SMOKE HAS FAILURES ❌"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
