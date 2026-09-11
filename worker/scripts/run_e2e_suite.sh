#!/usr/bin/env bash
# =============================================================================
# plan2_final — Consolidated E2E Test Runner (Phase H)
# Chạy TOÀN BỘ evidence suite: Phase A (security), B (lifecycle),
# C (concurrency), D (matching matrix), E (maps/geocode).
#
# Mỗi lần chạy: patch TẤT CẢ số phone test thành số MỚI (run tag = giây epoch)
# → user mới hoàn toàn → không bị dữ liệu/rate-limit của run trước làm nhiễu.
# Yêu cầu: wrangler dev đang chạy ở :8787 với MAPS_PROVIDER=mock, ALLOW_DEV_OTP=true.
# =============================================================================
set -u
cd "$(dirname "$0")/.."   # worker/

RUN_TAG=$(date +%s | tail -c 5)   # 4 chữ số cuối của epoch — đổi mỗi giây
TOTAL_PASS=0; TOTAL_FAIL=0

# Map mọi phone +84XXXXXXXXX (9 số sau +84) → phone mới: +849 + RUN_TAG + seq(4)
python3 - "$RUN_TAG" <<'PYEOF' > /tmp/e2e_phone_map.sed
import re, sys
run_tag = sys.argv[1]
phones = {}
for name in ["phaseA", "phaseB", "phaseC", "phaseD", "phaseE"]:
    try:
        with open(f"/tmp/e2e_{name}.sh") as f:
            for m in re.finditer(r"\+84\d{9}", f.read()):
                phones.setdefault(m.group(0), len(phones) + 1)
    except FileNotFoundError:
        pass
for phone, seq in phones.items():
    print(f"s|{phone}|+849{run_tag}{seq:04d}|g")
PYEOF

run_suite() { # name script_path
  local name
  local script
  local patched
  name="$1"
  script="$2"
  patched="/tmp/e2e_${name}_run.sh"
  if [ ! -f "$script" ]; then
    echo "SKIP: $name ($script không tồn tại)"
    return
  fi
  echo "======================================================================"
  echo ">>> SUITE: $name"
  sed -f /tmp/e2e_phone_map.sed "$script" > "$patched"
  bash "$patched" 2>&1 | tee "/tmp/suite_${name}.log" | grep -E "^(PASS|FAIL):" || true
  local p f
  p=$(grep -c "^PASS:" "/tmp/suite_${name}.log" || true)
  f=$(grep -c "^FAIL:" "/tmp/suite_${name}.log" || true)
  TOTAL_PASS=$((TOTAL_PASS+p))
  TOTAL_FAIL=$((TOTAL_FAIL+f))
  echo ">>> $name: PASS=$p FAIL=$f"
}

run_suite PhaseA /tmp/e2e_phaseA.sh
run_suite PhaseB /tmp/e2e_phaseB.sh
run_suite PhaseC /tmp/e2e_phaseC.sh
run_suite PhaseD /tmp/e2e_phaseD.sh
run_suite PhaseE /tmp/e2e_phaseE.sh

echo "======================================================================"
echo "TOTAL: PASS=$TOTAL_PASS FAIL=$TOTAL_FAIL"
if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo "E2E SUITE: ALL GREEN"
else
  echo "E2E SUITE: HAS FAILURES"
  exit 1
fi
