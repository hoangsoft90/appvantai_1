#!/usr/bin/env bash
# =============================================================================
# phase7 — E2E Mục 5: Prod-like smoke (DoD "flow chính pass trên môi trường
# gần prod" + "login production không dùng dev OTP")
#
# Server chạy bằng CẤU HÌNH [env.production] THẬT (wrangler dev --env production)
#   → APP_ENV=production, ALLOW_DEV_OTP=false (khác pilot_smoke.sh chạy dev)
# Login: customer+driver qua POST /auth/firebase với ID token test-signed
#   (JWT app trả về dùng xuyên suốt vòng lặp — chứng minh auth production thật)
# Guard: request-otp trên server production KHÔNG trả dev_otp
# Flow: match → contact → accept → lifecycle → complete (data seed Phase 6)
# =============================================================================
set -u
cd "$(dirname "$0")/.."

BASE="http://localhost:8787"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1  -->  $2"; }
json() {
  # Hỗ trợ 2 kiểu gọi: json "<$json>" '<query>' HOẶC curl ... | json '<query>'
  if [ $# -ge 2 ]; then printf '%s' "$1" | jq -r "$2" 2>/dev/null; else jq -r "$1" 2>/dev/null; fi
}

TAG=$(date +%s)
PROJ="p7-smoke-proj"
FB_CUST="+8497${TAG: -5}61"
FB_DRV="+8497${TAG: -5}62"

echo "=== PHASE 7 MỤC 5: PROD-LIKE SMOKE (production config + firebase login) ==="

# ---- Setup: JWKS test server + wrangler dev --env production ----
pkill -f "test_firebase_sign" 2>/dev/null || true
pkill -f "worker[d]" 2>/dev/null || true
sleep 2
node scripts/test_firebase_sign.mjs serve 8788 > /tmp/p7_jwks5.log 2>&1 &
JWKS_PID=$!
sleep 1

npx wrangler d1 migrations apply appvantai --local > /dev/null 2>&1 || true
# Local D1 của env production là database RIÊNG (persist tách default env) →
# phải apply migrations riêng cho env production trước khi chạy.
npx wrangler d1 migrations apply appvantai --local --env production > /dev/null 2>&1 || true
# --env production dùng [env.production] thật: APP_ENV=production, ALLOW_DEV_OTP=false.
# JWT_SECRET + FIREBASE_* truyền --var (production thật: wrangler secret put / vars).
# fix_p7_1.md #1: thiếu JWT_SECRET → guard 503 mọi request, nên secret là BẮT BUỘC;
# FIREBASE_JWKS_URL=http://127.0.0.1:8788 được phép (guard chỉ chặn JWKS ngoài localhost).
(npx wrangler dev --port 8787 --env production --var MAPS_PROVIDER:mock \
  --var "JWT_SECRET:p7-m5-smoke-secret-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --var "FIREBASE_PROJECT_ID:$PROJ" \
  --var "FIREBASE_JWKS_URL:http://127.0.0.1:8788" > /tmp/p7_m5.log 2>&1 &)
for i in $(seq 1 30); do curl -s -o /dev/null "$BASE/health" && break; sleep 1; done

# ---- 5.1 Server production thật: /health + không dev OTP ----
H=$(curl -s "$BASE/health")
[ "$(json "$H" '.env')" = "production" ] && ok "5.1a /health env=production ([env.production])" || fail "5.1a health" "$H"
R=$(curl -s -X POST "$BASE/auth/request-otp" -H 'content-type: application/json' -d "{\"phone\":\"$FB_CUST\"}")
printf '%s' "$R" | grep -q "dev_otp" && fail "5.1b production không trả dev_otp" "$R" || ok "5.1b production không trả dev_otp"

# ---- 5.2 Login production: Firebase ID token → JWT app ----
NOW=$(date +%s)
fblogin() { # phone → JWT app
  local T=$(node scripts/test_firebase_sign.mjs token "$PROJ" "https://securetoken.google.com/$PROJ" $((NOW+3600)) "$1")
  curl -s -X POST "$BASE/auth/firebase" -H 'content-type: application/json' -d "{\"id_token\":\"$T\"}" | jq -r '.token // empty' 2>/dev/null
}
TOK_C=$(fblogin "$FB_CUST")
TOK_D=$(fblogin "$FB_DRV")
[ -n "$TOK_C" ] && ok "5.2a customer login qua /auth/firebase → JWT" || fail "5.2a customer firebase login" "(empty token)"
[ -n "$TOK_D" ] && ok "5.2b driver login qua /auth/firebase → JWT" || fail "5.2b driver firebase login" "(empty token)"

# ---- 5.3 JWT firebase dùng được thật: /me + PATCH onboarding ----
MP=$(curl -s "$BASE/me" -H "Authorization: Bearer $TOK_D" | json '.user.phone')
[ "$MP" = "$FB_DRV" ] && ok "5.3a GET /me đúng SĐT từ token Firebase" || fail "5.3a /me" "got: $MP"
curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'Content-Type: application/json' \
  -d '{"name":"P7 Customer","role":"customer"}' > /dev/null
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_C" > /dev/null
curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_D" -H 'Content-Type: application/json' \
  -d '{"name":"P7 Driver","role":"driver"}' > /dev/null
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_D" > /dev/null
# Driver cần xe để pass capacity filter (bài học từ plan4 M4.3)
curl -s -X PATCH "$BASE/me/vehicle" -H "Authorization: Bearer $TOK_D" -H 'Content-Type: application/json' \
  -d '{"vehicle_type":"truck","license_plate":"29P7-777.77","capacity_kg":5000,"vehicle_length_cm":600,"vehicle_width_cm":230,"vehicle_height_cm":230,"operating_area":"Hà Nội"}' > /dev/null
VR=$(curl -s "$BASE/me" -H "Authorization: Bearer $TOK_D" | json '.driver_profile.capacity_kg')
# /me trả driver_profile ở top-level
[ "$VR" = "5000" ] && ok "5.3b driver onboarding + vehicle qua JWT firebase" || fail "5.3b vehicle" "capacity: $VR"

# ---- 5.4 Flow chính trên server production: order → trip → match → accept → complete ----
HN="21.0285,105.8542"; HP="20.8449,106.6881"
# Contract thật (services/orders.ts): pickup_from/pickup_to bắt buộc, expires_at mặc định = pickup_to; response {order}
PF=$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ); PT=$(date -u -d '+12 hours' +%Y-%m-%dT%H:%M:%SZ)
O=$(curl -s -X POST "$BASE/orders" -H "Authorization: Bearer $TOK_C" -H 'Content-Type: application/json' \
  -d "{\"pickup_lat\":21.0285,\"pickup_lng\":105.8542,\"pickup_address\":\"Hà Nội - P7 smoke\",\"delivery_lat\":20.9,\"delivery_lng\":106.4,\"delivery_address\":\"Hải Dương - P7 smoke\",\"cargo_type\":\"general\",\"weight_kg\":800,\"length_cm\":200,\"width_cm\":150,\"height_cm\":120,\"vehicle_requirement\":\"any\",\"price\":1500000,\"pickup_from\":\"$PF\",\"pickup_to\":\"$PT\",\"notes\":\"p7prodlike\"}")
ORDER_ID=$(json "$O" '.order.id')
[ -n "$ORDER_ID" ] && [ "$ORDER_ID" != "null" ] && ok "5.4a tạo order (JWT firebase)" || fail "5.4a tạo order" "$(printf '%s' "$O" | jq -c '.error // .')"

T=$(curl -s -X POST "$BASE/trips" -H "Authorization: Bearer $TOK_D" -H 'Content-Type: application/json' \
  -d "{\"from_lat\":21.0285,\"from_lng\":105.8542,\"from_address\":\"Hà Nội\",\"to_lat\":20.8449,\"to_lng\":106.6881,\"to_address\":\"Hải Phòng\"}")
TRIP_ID=$(json "$T" '.data.id')
[ -n "$TRIP_ID" ] && [ "$TRIP_ID" != "null" ] && ok "5.4b tạo trip" || fail "5.4b tạo trip" "$(printf '%s' "$T" | jq -c '.error // .')"

M=$(curl -s -X POST "$BASE/trips/$TRIP_ID/matches" -H "Authorization: Bearer $TOK_D")
HIT=$(json "$M" "[.data[] | select(.order.id==\"$ORDER_ID\")][0]")
[ -n "$HIT" ] && [ "$HIT" != "null" ] && ok "5.4c radar thấy order (score=$(json "$HIT" '.score'))" || fail "5.4c match" "$(printf '%s' "$M" | head -c 300)"

ACC=$(curl -s -X POST "$BASE/orders/$ORDER_ID/accept" -H "Authorization: Bearer $TOK_D")
[ "$(json "$ACC" '.data.accepted')" = "true" ] && ok "5.4d accept (atomic)" || fail "5.4d accept" "$(printf '%s' "$ACC" | jq -c '.error // .')"

curl -s -X POST "$BASE/orders/$ORDER_ID/pickup" -H "Authorization: Bearer $TOK_D" > /dev/null
curl -s -X POST "$BASE/orders/$ORDER_ID/in-transit" -H "Authorization: Bearer $TOK_D" > /dev/null
curl -s -X POST "$BASE/orders/$ORDER_ID/delivered" -H "Authorization: Bearer $TOK_D" > /dev/null
CP=$(curl -s -X POST "$BASE/orders/$ORDER_ID/complete" -H "Authorization: Bearer $TOK_C")
[ "$(json "$CP" '.data.status')" = "completed" ] && ok "5.4e lifecycle → COMPLETED (vòng lặp hoàn tất trên prod-like)" || fail "5.4e complete" "$(printf '%s' "$CP" | jq -c '.error // .')"

# ---- Cleanup ----
pkill -f "worker[d]" 2>/dev/null || true
kill $JWKS_PID 2>/dev/null || true

echo ""
echo "==================================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "PROD-LIKE SMOKE ALL GREEN ✅" || echo "HAS FAILURES ❌"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
