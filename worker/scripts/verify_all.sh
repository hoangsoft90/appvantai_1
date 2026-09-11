#!/usr/bin/env bash
# =============================================================================
# plan2_final — Full verification (Phase H)
# 1. Worker typecheck
# 2. Backend E2E suite (A→E) trên wrangler dev mock
# 3. Flutter analyze + tests
# =============================================================================
set -u
cd "$(dirname "$0")/.."   # worker/
FAIL=0

echo "=== [1/3] Worker typecheck ==="
if npm run --silent typecheck > /tmp/h_typecheck.log 2>&1; then
  echo "PASS: tsc --noEmit clean"
else
  echo "FAIL: typecheck errors"; cat /tmp/h_typecheck.log | tail -10; FAIL=1
fi

echo "=== [2/3] Backend E2E suite ==="
pkill -f "worker[d]" 2>/dev/null || true
sleep 2
(npx wrangler dev --port 8787 --var MAPS_PROVIDER:mock --var ALLOW_DEV_OTP:true --var APP_ENV:dev > /tmp/h_wrangler.log 2>&1 &)
for i in $(seq 1 30); do
  curl -s -o /dev/null http://localhost:8787/health && break
  sleep 1
done
if strings /tmp/h_wrangler.log | grep -q "Address already in use"; then
  echo "FAIL: port 8787 bị chiếm — dừng server cũ trước khi chạy"
  FAIL=1
else
  if bash scripts/run_e2e_suite.sh > /tmp/h_suite.log 2>&1; then
    echo "PASS: E2E suite all green"
    grep "TOTAL:" /tmp/h_suite.log
  else
    echo "FAIL: E2E suite có failures"
    grep -E ">>>|TOTAL:" /tmp/h_suite.log
    FAIL=1
  fi
fi
pkill -f "worker[d]" 2>/dev/null || true

echo "=== [3/3] Flutter analyze + tests ==="
cd ../mobile
if timeout 170 flutter analyze --no-pub > /tmp/h_analyze.log 2>&1; then
  echo "PASS: flutter analyze clean"
else
  echo "FAIL: analyze issues"; tail -5 /tmp/h_analyze.log; FAIL=1
fi
if timeout 170 flutter test > /tmp/h_flutter_test.log 2>&1; then
  echo "PASS: flutter tests $(grep -oE '\+[0-9]+: All tests passed' /tmp/h_flutter_test.log | tail -1)"
else
  echo "FAIL: flutter tests"; grep -E "Some tests|-[0-9]+" /tmp/h_flutter_test.log | tail -3; FAIL=1
fi

echo "======================================================================"
[ "$FAIL" -eq 0 ] && echo "PHASE H FULL VERIFICATION: ALL GREEN ✅" || echo "PHASE H FULL VERIFICATION: FAILURES ❌"
exit "$FAIL"
