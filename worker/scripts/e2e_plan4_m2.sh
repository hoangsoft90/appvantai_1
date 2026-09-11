#!/usr/bin/env bash
# =============================================================================
# plan4_final — E2E Mục 2: Production guard
# - APP_ENV=production + ALLOW_DEV_OTP=true → response KHÔNG có dev_otp (ép false)
# - APP_ENV=dev + ALLOW_DEV_OTP=true        → response CÓ dev_otp (dev test dễ)
# - Production + dev secret → env guard log PRODUCTION_ENV_GUARD
# =============================================================================
set -u
cd "$(dirname "$0")/.."

BASE="http://localhost:8787"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1  -->  $2"; }

jqget() { printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$2" 2>/dev/null; }

start_server() { # env:otp log
  pkill -f "worker[d]" 2>/dev/null || true
  sleep 2
  (npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock --var "APP_ENV:$1" --var "ALLOW_DEV_OTP:$2" > "$3" 2>&1 &)
  for i in $(seq 1 30); do curl -s -o /dev/null "$BASE/health" && break; sleep 1; done
}

TAG=$(date +%s)
PHONE="+8495${TAG: -5}77"

echo "=== MỤC 2: PRODUCTION GUARD ==="

# ---- 2A. Production + ALLOW_DEV_OTP=true → KHÔNG trả dev_otp ----
start_server production true /tmp/p4_m2_prod.log
R=$(curl -s -X POST "$BASE/auth/request-otp" -H 'content-type: application/json' -d "{\"phone\":\"$PHONE\"}")
if printf '%s' "$R" | grep -q "dev_otp"; then
  fail "2.1 production KHÔNG trả dev_otp" "$R"
else
  ok "2.1 production KHÔNG trả dev_otp (bỏ qua ALLOW_DEV_OTP=true)"
fi

# ---- 2B. Production + dev secret → env guard log ERROR ----
sleep 1
if grep -q "PRODUCTION_ENV_GUARD" /tmp/p4_m2_prod.log; then
  ok "2.2 env guard log PRODUCTION_ENV_GUARD (dev OTP + dev secret)"
else
  fail "2.2 env guard log PRODUCTION_ENV_GUARD" "(không thấy log)"
fi
if grep -q "JWT_SECRET" /tmp/p4_m2_prod.log; then
  ok "2.3 guard chỉ rõ JWT_SECRET dev placeholder"
else
  fail "2.3 guard chỉ rõ JWT_SECRET dev placeholder" "$(tail -3 /tmp/p4_m2_prod.log)"
fi

# ---- 2C. Dev mode vẫn test OTP dễ ----
start_server dev true /tmp/p4_m2_dev.log
R=$(curl -s -X POST "$BASE/auth/request-otp" -H 'content-type: application/json' -d "{\"phone\":\"$PHONE\"}")
if printf '%s' "$R" | grep -q "dev_otp"; then
  ok "2.4 dev mode vẫn trả dev_otp (test OTP dễ)"
else
  fail "2.4 dev mode vẫn trả dev_otp" "$R"
fi

# ---- 2D. Production verify-otp vẫn hoạt động (không echo mã) ----
start_server production false /tmp/p4_m2_prod2.log
R=$(curl -s -X POST "$BASE/auth/request-otp" -H 'content-type: application/json' -d "{\"phone\":\"$PHONE\"}")
if printf '%s' "$R" | grep -q "dev_otp"; then
  fail "2.5 production + ALLOW_DEV_OTP=false không trả dev_otp" "$R"
else
  ok "2.5 production + ALLOW_DEV_OTP=false không trả dev_otp"
fi
CODE=$(printf '%s' "$R" | python3 -c "import sys,json;print(json.load(sys.stdin).get('ok'))" 2>/dev/null)
[ "$CODE" = "True" ] && ok "2.6 request-otp production vẫn ok=true" || fail "2.6 request-otp production" "$R"

echo ""
echo "==================================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL GREEN" || echo "HAS FAILURES"
pkill -f "worker[d]" 2>/dev/null || true
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
