#!/usr/bin/env bash
# =============================================================================
# plan4_final — E2E Mục 3: Role lock theo business state
# - Đơn accepted/pickup/in_transit/delivered → ROLE_LOCKED kể cả khi expires_at < now
# - Đơn posted hết hạn (expires_at < now) → được đổi role
# - Trip planned/active → vẫn chặn; sau end → mở
# =============================================================================
set -u
cd "$(dirname "$0")/.."

BASE="http://localhost:8787"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1  -->  $2"; }
check() { if printf '%s' "$3" | grep -q "$2"; then ok "$1"; else fail "$1" "$3"; fi; }

TAG=$(date +%s)
C1="+8496${TAG: -5}01"
D1="+8496${TAG: -5}02"

pkill -f "worker[d]" 2>/dev/null || true
sleep 2
npx wrangler d1 migrations apply appvantai --local > /dev/null 2>&1 || true
(npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock --var ALLOW_DEV_OTP:true --var APP_ENV:dev > /tmp/p4_m3_wrangler.log 2>&1 &)
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

curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"name":"Chủ Hàng"}' > /dev/null
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_C" > /dev/null
curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_D" -H 'content-type: application/json' -d '{"name":"Tài Xế","role":"driver"}' > /dev/null
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_D" > /dev/null

create_order() {
  jqget "$(curl -s -X POST "$BASE/orders" -H "Authorization: Bearer $1" -H 'content-type: application/json' -d '{
    "pickup_lat":21.02,"pickup_lng":105.83,"pickup_address":"Bắc Giang",
    "delivery_lat":20.98,"delivery_lng":105.82,"delivery_address":"Bắc Ninh",
    "cargo_type":"general","vehicle_requirement":"any","weight_kg":500,"price":800000,
    "pickup_from":"2030-01-01T01:00:00Z","pickup_to":"2030-01-01T08:00:00Z"}')" "d.get('order',{}).get('id','')"
}
set_order_status() { # id status — mô phỏng business state (hết hạn cửa sổ nhưng vẫn đang chạy)
  npx wrangler d1 execute appvantai --local --command \
    "UPDATE cargo_orders SET status='$2', expires_at='2020-01-01T00:00:00Z' WHERE id='$1'" > /dev/null 2>&1
}

echo "=== MỤC 3: ROLE LOCK THEO BUSINESS STATE ==="

# ---- 3A. Đơn posted ĐÃ HẾT HẠN → đổi role OK (soft state, hết hạn thì mở) ----
O_POSTED=$(create_order "$TOK_C")
set_order_status "$O_POSTED" "posted"
R=$(curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"role":"driver"}')
if printf '%s' "$R" | grep -q "ROLE_LOCKED"; then
  fail "3.1 posted hết hạn → đổi role OK" "$R"
else
  ok "3.1 posted hết hạn → đổi role OK"
fi
# quay lại customer cho các test sau
curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"role":"customer"}' > /dev/null

# ---- 3B. accepted (hết hạn expires_at) → ROLE_LOCKED ----
O_ACC=$(create_order "$TOK_C")
set_order_status "$O_ACC" "accepted"
R=$(curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"role":"driver"}')
check "3.2 accepted (hết hạn) → ROLE_LOCKED" "ROLE_LOCKED" "$R"

# ---- 3C. pickup → ROLE_LOCKED ----
set_order_status "$O_ACC" "pickup"
R=$(curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"role":"driver"}')
check "3.3 pickup (hết hạn) → ROLE_LOCKED" "ROLE_LOCKED" "$R"

# ---- 3D. in_transit → ROLE_LOCKED ----
set_order_status "$O_ACC" "in_transit"
R=$(curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"role":"driver"}')
check "3.4 in_transit (hết hạn) → ROLE_LOCKED" "ROLE_LOCKED" "$R"

# ---- 3E. delivered → ROLE_LOCKED ----
set_order_status "$O_ACC" "delivered"
R=$(curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"role":"driver"}')
check "3.5 delivered (hết hạn) → ROLE_LOCKED" "ROLE_LOCKED" "$R"

# ---- 3F. completed → mở khóa ----
set_order_status "$O_ACC" "completed"
R=$(curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"role":"driver"}')
if printf '%s' "$R" | grep -q "ROLE_LOCKED"; then
  fail "3.6 completed → mở khóa" "$R"
else
  ok "3.6 completed → mở khóa"
fi
curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"role":"customer"}' > /dev/null

# ---- 3G. onboarding lần đầu (chưa có đơn) vẫn OK — dùng user mới ----
C2="+8496${TAG: -5}03"
TOK_C2=$(login "$C2")
R=$(curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C2" -H 'content-type: application/json' -d '{"name":"Mới","role":"driver"}')
check "3.7 onboarding chọn role lần đầu OK" '"role": *"driver"' "$R"
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_C2" > /dev/null

# ---- 3H. Trip planned/active → vẫn chặn (giữ hành vi plan3) ----
TRIP=$(jqget "$(curl -s -X POST "$BASE/trips" -H "Authorization: Bearer $TOK_C2" -H 'content-type: application/json' -d '{
  "from_lat":21.03,"from_lng":105.84,"from_address":"Bắc Giang",
  "to_lat":21.00,"to_lng":105.83,"to_address":"Bắc Ninh","trip_type":"one_way"}')" "d.get('data',{}).get('id','')")
R=$(curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C2" -H 'content-type: application/json' -d '{"role":"customer"}')
check "3.8 trip planned → ROLE_LOCKED" "ROLE_LOCKED" "$R"
curl -s -X POST "$BASE/trips/$TRIP/end" -H "Authorization: Bearer $TOK_C2" > /dev/null
R=$(curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C2" -H 'content-type: application/json' -d '{"role":"customer"}')
if printf '%s' "$R" | grep -q "ROLE_LOCKED"; then
  fail "3.9 sau end trip → mở khóa" "$R"
else
  ok "3.9 sau end trip → mở khóa"
fi

echo ""
echo "==================================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL GREEN" || echo "HAS FAILURES"
pkill -f "worker[d]" 2>/dev/null || true
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
