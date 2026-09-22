#!/usr/bin/env bash
# P2GC-3 consecutive re-validation — runs the device suite N times.
# Usage: run_p2gc3.sh <runs>
set -u
RUNS="${1:-5}"
cd "$(dirname "$0")/.."

export ANDROID_SDK_ROOT="C:\Users\PORTCR\AppData\Local\Android\Sdk"
export PATH="/c/Users/PORTCR/AppData/Local/Android/Sdk/platform-tools:/h/flutter/bin:$PATH"

i=1
while [ "$i" -le "$RUNS" ]; do
  LOG="docs/evidence_p2gc_d3_p2gc3_run${i}_$(date +%Y-%m-%d).log"
  echo "===== P2GC-3 RUN $i ====="
  flutter test integration_test/phase2gc_device_verification_test.dart \
    -d R83L20FRDFM \
    --dart-define=P2GC_TEST_URL=http://192.168.29.246:8712/test.mp4 \
    --plain-name P2GC-3 > "$LOG" 2>&1
  echo "exit=$?"
  grep -E 'SPECTA-P2GC|All tests|Failed|Error|Exception|FAIL' "$LOG" | tail -6
  i=$((i + 1))
done