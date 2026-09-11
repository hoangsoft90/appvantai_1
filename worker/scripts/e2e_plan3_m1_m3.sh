#!/usr/bin/env bash
# =============================================================================
# plan3_final — E2E Mục 1 (Khóa role) + Mục 3 (GPS chỉ cho trip active)
# Standalone: tự start wrangler dev (mock maps, dev OTP), tự tạo user mới mỗi run
# (phone theo giây epoch) để không bị rate-limit/dữ liệu cũ làm nhiễu.
# =============================================================================
set -u
cd "$(dirname "$0")/.."

BASE="http://localhost:8787"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1  -->  $2"; }
check() { # name expected_sub actual
  if printf '%s' "$3" | grep -q "$2"; then ok "$1"; else fail "$1" "$3"; fi
}

# ---- phone duy nhất mỗi run ----
TAG=$(date +%s)
C1="+8493${TAG: -5}01"   # customer có active order
D1="+8493${TAG: -5}02"   # driver có trip planned
D2="+8493${TAG: -5}03"   # driver test GPS

# ---- start server ----
pkill -f "worker[d]" 2>/dev/null || true
sleep 2
npx wrangler d1 migrations apply appvantai --local > /dev/null 2>&1 || true
(npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock --var ALLOW_DEV_OTP:true --var APP_ENV:dev > /tmp/p3_wrangler.log 2>&1 &)
for i in $(seq 1 30); do curl -s -o /dev/null "$BASE/health" && break; sleep 1; done

jqget() { printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$2" 2>/dev/null; }

# login: request-otp 1 lần, retry CHỈ verify (tránh cạn rate limit OTP)
login() { # phone -> token (stdout)
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
me_patch() { # token json -> body
  curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $1" -H 'content-type: application/json' -d "$2"
}

# ---- setup users ----
TOK_C1=$(login "$C1")
TOK_D1=$(login "$D1")
TOK_D2=$(login "$D2")
if [ -z "$TOK_C1" ] || [ -z "$TOK_D1" ] || [ -z "$TOK_D2" ]; then
  echo "FAIL: setup login"; strings /tmp/p3_wrangler.log | tail -5; exit 1
fi

role_driver() { # token
  curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $1" -H 'content-type: application/json' -d '{"name":"Test User","role":"driver"}' > /dev/null
  curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $1" > /dev/null
}
role_driver "$TOK_D1"
role_driver "$TOK_D2"
# Customer cũng cần consent trước khi tạo đơn (POST /orders enforce §1.4)
curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C1" -H 'content-type: application/json' -d '{"name":"Chủ Hàng"}' > /dev/null
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_C1" > /dev/null

create_order() { # token -> id
  jqget "$(curl -s -X POST "$BASE/orders" -H "Authorization: Bearer $1" -H 'content-type: application/json' -d '{
    "pickup_lat":21.02,"pickup_lng":105.83,"pickup_address":"Bắc Giang",
    "delivery_lat":20.98,"delivery_lng":105.82,"delivery_address":"Bắc Ninh",
    "cargo_type":"general","vehicle_requirement":"any","weight_kg":500,"price":800000,
    "pickup_from":"2030-01-01T01:00:00Z","pickup_to":"2030-01-01T08:00:00Z"}')" "d.get('order',{}).get('id','')"
}
create_trip() { # token -> id
  jqget "$(curl -s -X POST "$BASE/trips" -H "Authorization: Bearer $1" -H 'content-type: application/json' -d '{
    "from_lat":21.03,"from_lng":105.84,"from_address":"Bắc Giang",
    "to_lat":21.00,"to_lng":105.83,"to_address":"Bắc Ninh","trip_type":"one_way"}')" "d.get('data',{}).get('id','')"
}

ORDER1=$(create_order "$TOK_C1")
TRIP1=$(create_trip "$TOK_D1")
TRIP2=$(create_trip "$TOK_D2")

echo "=== MỤC 1: KHÓA ROLE ==="

# 1.1 Customer đang có active order → đổi role bị chặn
R=$(me_patch "$TOK_C1" '{"role":"driver"}')
check "1.1 đổi role khi có active order → 409 ROLE_LOCKED" "ROLE_LOCKED" "$R"

# 1.2 Re-submit cùng role (onboarding bấm lại) → vẫn cho qua
R=$(me_patch "$TOK_C1" '{"role":"customer"}')
check "1.2 re-submit cùng role → 200 (idempotent onboarding)" '"role": *"customer"' "$R"

# 1.3 Đổi tên không bị chặn bởi role lock
R=$(me_patch "$TOK_C1" '{"name":"Chủ Hàng Bắc Giang"}')
check "1.3 đổi tên khi có active order → 200" "Chủ Hàng Bắc Giang" "$R"

# 1.4 Sau khi hủy đơn → đổi role được
curl -s -X POST "$BASE/orders/$ORDER1/cancel" -H "Authorization: Bearer $TOK_C1" > /dev/null
R=$(me_patch "$TOK_C1" '{"role":"driver"}')
check "1.4 đổi role sau khi hủy đơn → 200" '"role": *"driver"' "$R"

# 1.5 Driver đang có trip planned → đổi role bị chặn (cả 2 chiều: guard check
# trước khi UPDATE nên driver→customer và customer→driver đều dính ROLE_LOCKED)
R=$(me_patch "$TOK_D1" '{"role":"customer"}')
check "1.5 driver→customer khi có trip planned → 409 ROLE_LOCKED" "ROLE_LOCKED" "$R"

# 1.7 End trip → đổi role được
curl -s -X POST "$BASE/trips/$TRIP1/end" -H "Authorization: Bearer $TOK_D1" > /dev/null
R=$(me_patch "$TOK_D1" '{"role":"customer"}')
check "1.7 đổi role sau khi end trip → 200" '"role": *"customer"' "$R"

echo "=== MỤC 3: GPS CHỈ CHO TRIP ACTIVE ==="

# 3.1 Trip planned → gửi GPS bị reject
R=$(curl -s -X POST "$BASE/trips/$TRIP2/location" -H "Authorization: Bearer $TOK_D2" -H 'content-type: application/json' -d '{"lat":21.03,"lng":105.84}')
check "3.1 GPS khi trip planned → 400 TRIP_NOT_ACTIVE" "TRIP_NOT_ACTIVE" "$R"

# 3.2 Start trip → GPS được ghi
R=$(curl -s -X POST "$BASE/trips/$TRIP2/start" -H "Authorization: Bearer $TOK_D2")
check "3.2 start trip → active" '"status": *"active"' "$R"
R=$(curl -s -X POST "$BASE/trips/$TRIP2/location" -H "Authorization: Bearer $TOK_D2" -H 'content-type: application/json' -d '{"lat":21.03,"lng":105.84}')
if printf '%s' "$R" | grep -q '"error"'; then fail "3.3 GPS khi trip active → 200" "$R"; else ok "3.3 GPS khi trip active → 200"; fi

# 3.4 End trip → GPS bị reject lần nữa + KV đã xóa
curl -s -X POST "$BASE/trips/$TRIP2/end" -H "Authorization: Bearer $TOK_D2" > /dev/null
R=$(curl -s -X POST "$BASE/trips/$TRIP2/location" -H "Authorization: Bearer $TOK_D2" -H 'content-type: application/json' -d '{"lat":21.03,"lng":105.84}')
check "3.4 GPS sau khi end → 400 TRIP_NOT_ACTIVE" "TRIP_NOT_ACTIVE" "$R"

# 3.5 Customer (đã consent) không gửi được GPS (role gate)
TOK_C2=$(login "+8493${TAG: -5}04")
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_C2" > /dev/null
R=$(curl -s -X POST "$BASE/trips/$TRIP2/location" -H "Authorization: Bearer $TOK_C2" -H 'content-type: application/json' -d '{"lat":21.03,"lng":105.84}')
check "3.5 customer gửi GPS → 403" "FORBIDDEN\|Chỉ tài xế" "$R"

echo "======================================================================"
echo "plan3 M1+M3: PASS=$PASS FAIL=$FAIL"
pkill -f "worker[d]" 2>/dev/null || true
[ "$FAIL" -eq 0 ] && echo "plan3 M1+M3: ALL GREEN" || exit 1
