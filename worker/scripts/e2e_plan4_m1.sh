#!/usr/bin/env bash
# =============================================================================
# plan4_final — E2E Mục 1: Siết customer cancel (P0)
# Customer CHỈ cancel được ở posted/matched/contacted.
# Từ accepted trở đi → 409 CANCEL_NOT_ALLOWED.
# Standalone: tự start wrangler dev (mock maps, dev OTP), phone unique mỗi run.
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

TAG=$(date +%s)
C1="+8494${TAG: -5}01"   # customer
D1="+8494${TAG: -5}02"   # driver

pkill -f "worker[d]" 2>/dev/null || true
sleep 2
npx wrangler d1 migrations apply appvantai --local > /dev/null 2>&1 || true
(npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock --var ALLOW_DEV_OTP:true --var APP_ENV:dev > /tmp/p4_m1_wrangler.log 2>&1 &)
for i in $(seq 1 30); do curl -s -o /dev/null "$BASE/health" && break; sleep 1; done

jqget() { printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$2" 2>/dev/null; }

login() { # phone -> token
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
if [ -z "$TOK_C" ] || [ -z "$TOK_D" ]; then
  echo "FAIL: setup login"; strings /tmp/p4_m1_wrangler.log | tail -5; exit 1
fi

curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_C" -H 'content-type: application/json' -d '{"name":"Chủ Hàng"}' > /dev/null
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_C" > /dev/null
curl -s -X PATCH "$BASE/me" -H "Authorization: Bearer $TOK_D" -H 'content-type: application/json' -d '{"name":"Tài Xế","role":"driver"}' > /dev/null
curl -s -X POST "$BASE/me/legal-consent" -H "Authorization: Bearer $TOK_D" > /dev/null

create_order() { # token -> id
  jqget "$(curl -s -X POST "$BASE/orders" -H "Authorization: Bearer $1" -H 'content-type: application/json' -d '{
    "pickup_lat":21.02,"pickup_lng":105.83,"pickup_address":"Bắc Giang",
    "delivery_lat":20.98,"delivery_lng":105.82,"delivery_address":"Bắc Ninh",
    "cargo_type":"general","vehicle_requirement":"any","weight_kg":500,"price":800000,
    "pickup_from":"2030-01-01T01:00:00Z","pickup_to":"2030-01-01T08:00:00Z"}')" "d.get('order',{}).get('id','')"
}

cancel() { # token order_id -> body
  curl -s -X POST "$BASE/orders/$2/cancel" -H "Authorization: Bearer $1"
}

echo "=== MỤC 1: SIẾT CUSTOMER CANCEL ==="

# ---- 1A. posted → cancel OK ----
O_POSTED=$(create_order "$TOK_C")
R=$(cancel "$TOK_C" "$O_POSTED")
check "1.1 posted → cancel OK" '"status": *"cancelled"' "$R"

# ---- 1B. contacted → cancel OK ----
O_CONTACT=$(create_order "$TOK_C")
curl -s -X POST "$BASE/orders/$O_CONTACT/contact" -H "Authorization: Bearer $TOK_D" > /dev/null
R=$(cancel "$TOK_C" "$O_CONTACT")
check "1.2 contacted → cancel OK" '"status": *"cancelled"' "$R"

# ---- 1C. matched → cancel OK (set trạng thái matched trực tiếp qua SQL: pipeline
#      thật chỉ gán matched gián tiếp qua matches view, không đổi cột status) ----
O_MATCH=$(create_order "$TOK_C")
npx wrangler d1 execute appvantai --local --command \
  "UPDATE cargo_orders SET status='matched' WHERE id='$O_MATCH'" > /dev/null 2>&1
R=$(cancel "$TOK_C" "$O_MATCH")
check "1.3 matched → cancel OK" '"status": *"cancelled"' "$R"

# ---- 1D. accepted → CANCEL_NOT_ALLOWED ----
O_ACC=$(create_order "$TOK_C")
curl -s -X POST "$BASE/orders/$O_ACC/accept" -H "Authorization: Bearer $TOK_D" > /dev/null
R=$(cancel "$TOK_C" "$O_ACC")
check "1.4 accepted → cancel bị chặn (409 CANCEL_NOT_ALLOWED)" "CANCEL_NOT_ALLOWED" "$R"
CODE=$(printf '%s' "$R" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['error']['status'])" 2>/dev/null)
check "1.5 HTTP status của CANCEL_NOT_ALLOWED = 409" "^409$" "$CODE"

# ---- 1E. pickup → CANCEL_NOT_ALLOWED ----
curl -s -X POST "$BASE/orders/$O_ACC/pickup" -H "Authorization: Bearer $TOK_D" > /dev/null
R=$(cancel "$TOK_C" "$O_ACC")
check "1.6 pickup → cancel bị chặn" "CANCEL_NOT_ALLOWED" "$R"

# ---- 1F. in_transit → CANCEL_NOT_ALLOWED ----
curl -s -X POST "$BASE/orders/$O_ACC/in-transit" -H "Authorization: Bearer $TOK_D" > /dev/null
R=$(cancel "$TOK_C" "$O_ACC")
check "1.7 in_transit → cancel bị chặn" "CANCEL_NOT_ALLOWED" "$R"

# ---- 1G. delivered → CANCEL_NOT_ALLOWED ----
curl -s -X POST "$BASE/orders/$O_ACC/delivered" -H "Authorization: Bearer $TOK_D" > /dev/null
R=$(cancel "$TOK_C" "$O_ACC")
check "1.8 delivered → cancel bị chặn" "CANCEL_NOT_ALLOWED" "$R"

# ---- 1H. delivered → customer complete OK (flow lifecycle không vỡ) ----
R=$(curl -s -X POST "$BASE/orders/$O_ACC/complete" -H "Authorization: Bearer $TOK_C")
check "1.9 delivered → complete OK (flow chính không ảnh hưởng)" '"status": *"completed"' "$R"

# ---- 1I. CANCEL_NOT_ALLOWED ưu tiên INVALID_TRANSITION ----
O2=$(create_order "$TOK_C")
curl -s -X POST "$BASE/orders/$O2/accept" -H "Authorization: Bearer $TOK_D" > /dev/null
R=$(cancel "$TOK_C" "$O2")
check "1.10 mã lỗi ổn định CANCEL_NOT_ALLOWED (không INVALID_TRANSITION)" "CANCEL_NOT_ALLOWED" "$R"
if printf '%s' "$R" | grep -q "INVALID_TRANSITION"; then
  fail "1.11 không trả INVALID_TRANSITION chung" "$R"
else
  ok "1.11 không trả INVALID_TRANSITION chung"
fi

# ---- 1J. OTHER user cancel không leak (404 như cũ) ----
TOK_D2_JSON=$(curl -s -X POST "$BASE/auth/request-otp" -H 'content-type: application/json' -d "{\"phone\":\"+8494${TAG: -5}03\"}")
OTP_D2=$(jqget "$TOK_D2_JSON" "d.get('dev_otp','')")
TOK_D2=$(jqget "$(curl -s -X POST "$BASE/auth/verify-otp" -H 'content-type: application/json' -d "{\"phone\":\"+8494${TAG: -5}03\",\"otp\":\"$OTP_D2\"}")" "d.get('token','')")
R=$(cancel "$TOK_D2" "$O2")
check "1.12 người ngoài cancel → 404 không leak" "ORDER_NOT_FOUND" "$R"

echo ""
echo "==================================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL GREEN" || echo "HAS FAILURES"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
