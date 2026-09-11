#!/usr/bin/env bash
# =============================================================================
# phase7 — E2E Mục 1: Env/secrets + production guard (fix_p7_1.md #1)
# - [env.production] trong wrangler.toml: APP_ENV=production, ALLOW_DEV_OTP=false
#   (chạy bằng cấu hình production THẬT, không phải --var override như plan4 M2)
# - JWT_SECRET KHÔNG còn fallback trong [env.production.vars] — production đúng
#   cấu hình = --var/secret JWT_SECRET + FIREBASE_PROJECT_ID (mô phỏng wrangler secret)
# - Production ĐÚNG cấu hình → /health 200, không trả dev_otp
# - Production SAI cấu hình (thiếu JWT_SECRET) → MỌI request 503
#   PRODUCTION_MISCONFIGURED (fail-fast, không chỉ log)
# - APP_ENV=dev vẫn trả dev_otp (local dev không bị phá)
# =============================================================================
set -u
cd "$(dirname "$0")/.."

BASE="http://localhost:8787"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1  -->  $2"; }

start_server() { # $1=extra wrangler args, $2=log
  pkill -f "worker[d]" 2>/dev/null || true
  sleep 2
  (npx wrangler dev --port 8787 $1 > "$2" 2>&1 &)
  for i in $(seq 1 30); do curl -s -o /dev/null "$BASE/health" && break; sleep 1; done
}

TAG=$(date +%s)
PHONE="+8497${TAG: -5}21"
RAND=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')

echo "=== PHASE 7 MỤC 1: ENV/SECRETS + GUARD ==="

# ---- 1A. Cấu hình [env.production] THẬT + secret/project đầy đủ (happy path) ----
# (production thật: JWT_SECRET + FIREBASE_PROJECT_ID đặt qua wrangler secret;
#  local mô phỏng bằng --var — cùng đường vào env object)
start_server "--env production --var JWT_SECRET:$RAND --var FIREBASE_PROJECT_ID:p7-m1-proj" /tmp/p7_m1_prod.log

R=$(curl -s "$BASE/health")
if printf '%s' "$R" | grep -q '"env":"production"'; then
  ok "1.1 /health báo env=production (từ [env.production])"
else
  fail "1.1 /health env=production" "$R"
fi

R=$(curl -s -X POST "$BASE/auth/request-otp" -H 'content-type: application/json' -d "{\"phone\":\"$PHONE\"}")
if printf '%s' "$R" | grep -q "dev_otp"; then
  fail "1.2 production không trả dev_otp (cấu hình [env.production])" "$R"
else
  ok "1.2 production không trả dev_otp (cấu hình [env.production])"
fi
if printf '%s' "$R" | grep -q '"ok":true'; then
  ok "1.3 request-otp production vẫn ok=true (OTP lưu KV, không echo)"
else
  fail "1.3 request-otp ok=true" "$R"
fi

# ---- 1B. Production SAI cấu hình (thiếu JWT_SECRET) → 503 fail-fast ----
# (fix_p7_1.md #1: trước đây chỉ log ERROR — giờ mọi request bị chặn 503)
start_server "--env production" /tmp/p7_m1_misconf.log
CODE=$(curl -s -o /tmp/p7_m1_misconf_body -w "%{http_code}" "$BASE/health")
if [ "$CODE" = "503" ] && grep -q "PRODUCTION_MISCONFIGURED" /tmp/p7_m1_misconf_body; then
  ok "1.4 production thiếu JWT_SECRET → 503 PRODUCTION_MISCONFIGURED (fail-fast)"
else
  fail "1.4 guard fail-fast 503" "HTTP $CODE: $(cat /tmp/p7_m1_misconf_body)"
fi
for i in $(seq 1 10); do grep -q "PRODUCTION_ENV_GUARD" /tmp/p7_m1_misconf.log && break; sleep 1; done
if grep -q "JWT_SECRET" /tmp/p7_m1_misconf.log; then
  ok "1.5 guard log chỉ rõ nguyên nhân JWT_SECRET (chẩn đoán được)"
else
  fail "1.5 guard log JWT_SECRET" "$(tail -3 /tmp/p7_m1_misconf.log)"
fi

# ---- 1C. Dev mode không bị phá ----
start_server "" /tmp/p7_m1_dev.log
R=$(curl -s -X POST "$BASE/auth/request-otp" -H 'content-type: application/json' -d "{\"phone\":\"$PHONE\"}")
if printf '%s' "$R" | grep -q "dev_otp"; then
  ok "1.5 dev mode vẫn trả dev_otp (local dev giữ nguyên)"
else
  fail "1.5 dev mode trả dev_otp" "$R"
fi

echo ""
echo "==================================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL GREEN" || echo "HAS FAILURES"
pkill -f "worker[d]" 2>/dev/null || true
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
