#!/usr/bin/env bash
# =============================================================================
# phase7 — E2E Mục 2: Auth production (Firebase Phone Auth)
# Verify server-side của Firebase ID token (RS256 + JWKS) KHÔNG cần project thật:
# keypair local + JWKS server 127.0.0.1:8788 → Worker verify qua FIREBASE_JWKS_URL
# (chỉ phép ở dev/test; production guard cấm — test ở case 2.9).
#
# Case:
#  2.1  Token hợp lệ → 200 {token,user}, user mới role=customer
#  2.2  Same phone lần 2 (uid khác) → CÙNG user id (upsert theo phone)
#  2.3  aud sai (khác project) → 401 INVALID_ID_TOKEN
#  2.4  Token hết hạn → 401
#  2.5  Token rác → 401
#  2.6  Chữ ký bị giả mạo → 401
#  2.7  JWT app trả về dùng được thật: GET /me với Authorization
#  2.8  firebase_uid được ghi vào D1
#  2.9  Production guard: cấm FIREBASE_JWKS_URL + cảnh báo thiếu FIREBASE_PROJECT_ID
#  2.10 Dev OTP (/auth/request-otp) vẫn chạy song song không bị phá
# =============================================================================
set -u
cd "$(dirname "$0")/.."

BASE="http://localhost:8787"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1  -->  $2"; }

jqget() { printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$2" 2>/dev/null; }

TAG=$(date +%s)
PHONE="+8497${TAG: -5}33"
PROJ="p7-test-proj"

echo "=== PHASE 7 MỤC 2: FIREBASE PHONE AUTH ==="

# ---- Setup: JWKS test server + wrangler dev với Firebase env ----
pkill -f "test_firebase_sign" 2>/dev/null || true
pkill -f "worker[d]" 2>/dev/null || true
sleep 1
node scripts/test_firebase_sign.mjs serve 8788 > /tmp/p7_jwks.log 2>&1 &
JWKS_PID=$!
sleep 1

(npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock \
  --var "FIREBASE_PROJECT_ID:$PROJ" \
  --var "FIREBASE_JWKS_URL:http://127.0.0.1:8788" > /tmp/p7_m2.log 2>&1 &)
for i in $(seq 1 30); do curl -s -o /dev/null "$BASE/health" && break; sleep 1; done

NOW=$(date +%s)

# ---- 2.1 Token hợp lệ → đăng nhập được ----
TOK=$(node scripts/test_firebase_sign.mjs token "$PROJ" "https://securetoken.google.com/$PROJ" $((NOW+3600)) "$PHONE")
R=$(curl -s -X POST "$BASE/auth/firebase" -H 'content-type: application/json' -d "{\"id_token\":\"$TOK\"}")
UID1=$(jqget "$R" "d['user']['id']")
if [ -n "$UID1" ] && [ "$UID1" != "None" ]; then
  ok "2.1 token hợp lệ → 200 user id=$UID1"
else
  fail "2.1 token hợp lệ đăng nhập" "$R"
fi
APPJWT=$(jqget "$R" "d['token']")

# ---- 2.2 Same phone, uid khác → cùng user (upsert theo phone) ----
TOK2=$(node scripts/test_firebase_sign.mjs token "$PROJ" "https://securetoken.google.com/$PROJ" $((NOW+3600)) "$PHONE" "other-uid-xyz")
R=$(curl -s -X POST "$BASE/auth/firebase" -H 'content-type: application/json' -d "{\"id_token\":\"$TOK2\"}")
UID2=$(jqget "$R" "d['user']['id']")
if [ "$UID2" = "$UID1" ]; then
  ok "2.2 login lại cùng SĐT (uid khác) → cùng user id (upsert theo phone)"
else
  fail "2.2 upsert theo phone" "uid1=$UID1 uid2=$UID2"
fi

# ---- 2.3 aud sai → 401 ----
TOK3=$(node scripts/test_firebase_sign.mjs token "other-project" "https://securetoken.google.com/other-project" $((NOW+3600)) "$PHONE")
CODE=$(curl -s -o /tmp/p7_r23 -w "%{http_code}" -X POST "$BASE/auth/firebase" -H 'content-type: application/json' -d "{\"id_token\":\"$TOK3\"}")
if [ "$CODE" = "401" ] && grep -q "INVALID_ID_TOKEN" /tmp/p7_r23; then
  ok "2.3 aud/iss không khớp project → 401 INVALID_ID_TOKEN"
else
  fail "2.3 aud sai" "HTTP $CODE: $(cat /tmp/p7_r23)"
fi

# ---- 2.4 Token hết hạn → 401 ----
TOK4=$(node scripts/test_firebase_sign.mjs token "$PROJ" "https://securetoken.google.com/$PROJ" $((NOW-600)) "$PHONE")
CODE=$(curl -s -o /tmp/p7_r24 -w "%{http_code}" -X POST "$BASE/auth/firebase" -H 'content-type: application/json' -d "{\"id_token\":\"$TOK4\"}")
if [ "$CODE" = "401" ]; then
  ok "2.4 token hết hạn → 401"
else
  fail "2.4 token hết hạn" "HTTP $CODE: $(cat /tmp/p7_r24)"
fi

# ---- 2.5 Token rác → 401 ----
CODE=$(curl -s -o /tmp/p7_r25 -w "%{http_code}" -X POST "$BASE/auth/firebase" -H 'content-type: application/json' -d '{"id_token":"not.a.jwt"}')
if [ "$CODE" = "401" ]; then
  ok "2.5 token rác → 401"
else
  fail "2.5 token rác" "HTTP $CODE: $(cat /tmp/p7_r25)"
fi

# ---- 2.6 Chữ ký giả mạo → 401 (đổi payload sau khi ký) ----
TOK6=$(node scripts/test_firebase_sign.mjs token "$PROJ" "https://securetoken.google.com/$PROJ" $((NOW+3600)) "$PHONE")
H_P=$(printf '%s' "$TOK6" | cut -d. -f1-2)
FAKE_PAYLOAD=$(printf '%s' "$TOK6" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);d['phone_number']='+849012345678';print(json.dumps(d))" | base64 -w0 | tr '/+' '_-' | tr -d '=')
TAMPERED="${H_P}.${FAKE_PAYLOAD}.$(printf '%s' "$TOK6" | cut -d. -f3)"
CODE=$(curl -s -o /tmp/p7_r26 -w "%{http_code}" -X POST "$BASE/auth/firebase" -H 'content-type: application/json' -d "{\"id_token\":\"$TAMPERED\"}")
if [ "$CODE" = "401" ]; then
  ok "2.6 payload bị sửa sau khi ký → 401 (signature verify chặn)"
else
  fail "2.6 chữ ký giả mạo" "HTTP $CODE: $(cat /tmp/p7_r26)"
fi

# ---- 2.7 JWT app dùng được thật: GET /me ----
R=$(curl -s "$BASE/me" -H "Authorization: Bearer $APPJWT")
MEPHONE=$(jqget "$R" "d['user']['phone']")
if [ "$MEPHONE" = "$PHONE" ]; then
  ok "2.7 JWT từ /auth/firebase dùng được: GET /me → đúng SĐT"
else
  fail "2.7 GET /me với JWT firebase" "$R"
fi

# ---- 2.8 firebase_uid ghi vào D1 ----
RU=$(npx wrangler d1 execute appvantai --local --json --command \
  "SELECT firebase_uid FROM users WHERE id='$UID1'" 2>/dev/null | python3 -c "import sys,json;rows=json.load(sys.stdin);print(rows[0]['results'][0]['firebase_uid'])" 2>/dev/null)
FBUID=$(node scripts/test_firebase_sign.mjs token "$PROJ" "https://securetoken.google.com/$PROJ" $((NOW+3600)) "$PHONE" "probe-uid-x" > /dev/null; python3 -c "import json;print(json.load(open('/tmp/p7_fb_key.json'))['kid'])" 2>/dev/null)
if [ -n "$RU" ] && [ "$RU" != "None" ] && [ "$RU" != "probe-uid-x" ]; then
  ok "2.8 firebase_uid đã ghi vào D1 ($RU)"
else
  fail "2.8 firebase_uid trong D1" "got: $RU"
fi

# ---- 2.9 Production guard (fix_p7_1.md #1): JWKS ngoài localhost + thiếu secret → 503 ----
# (JWKS localhost được phép cho test/CI — cửa hậu còn lại bị đóng: mọi URL khác
#  hoặc thiếu JWT_SECRET/FIREBASE_PROJECT_ID → mọi request 503 PRODUCTION_MISCONFIGURED)
pkill -f "worker[d]" 2>/dev/null || true
sleep 2
(npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock --var "APP_ENV:production" --var "ALLOW_DEV_OTP:false" \
  --var "FIREBASE_JWKS_URL:http://evil.example.com/jwks" > /tmp/p7_m2_prod.log 2>&1 &)
sleep 4
CODE=$(curl -s -o /tmp/p7_r29 -w "%{http_code}" "$BASE/health")
if [ "$CODE" = "503" ] && grep -q "PRODUCTION_MISCONFIGURED" /tmp/p7_r29; then
  ok "2.9a production JWKS ngoài localhost + thiếu secret → 503 PRODUCTION_MISCONFIGURED"
else
  fail "2.9a guard fail-fast 503" "HTTP $CODE: $(cat /tmp/p7_r29)"
fi
for i in $(seq 1 10); do grep -q "PRODUCTION_ENV_GUARD" /tmp/p7_m2_prod.log && break; sleep 1; done
G=0
grep -q "FIREBASE_JWKS_URL chỉ cho phép localhost" /tmp/p7_m2_prod.log && G=$((G+1))
grep -q "JWT_SECRET" /tmp/p7_m2_prod.log && G=$((G+1))
if [ "$G" -eq 2 ]; then
  ok "2.9b guard log chỉ rõ JWKS_URL + JWT_SECRET (chẩn đoán được)"
else
  fail "2.9b guard log" "$(grep -a PRODUCTION_ENV_GUARD /tmp/p7_m2_prod.log | tail -1)"
fi

# ---- 2.10 Dev OTP vẫn chạy song song ----
pkill -f "worker[d]" 2>/dev/null || true
sleep 2
(npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock > /tmp/p7_m2_dev.log 2>&1 &)
for i in $(seq 1 30); do curl -s -o /dev/null "$BASE/health" && break; sleep 1; done
R=$(curl -s -X POST "$BASE/auth/request-otp" -H 'content-type: application/json' -d "{\"phone\":\"$PHONE\"}")
if printf '%s' "$R" | grep -q "dev_otp"; then
  ok "2.10 dev OTP vẫn chạy song song (APP_ENV=dev)"
else
  fail "2.10 dev OTP không bị phá" "$R"
fi

# ---- Cleanup ----
pkill -f "worker[d]" 2>/dev/null || true
kill $JWKS_PID 2>/dev/null || true

echo ""
echo "==================================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL GREEN" || echo "HAS FAILURES"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
