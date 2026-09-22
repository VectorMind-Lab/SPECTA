#!/usr/bin/env bash
# D-3 device re-validation run — one invocation of the P2GC device suite.
# Usage: run_d3_device.sh <run-name> [extra flutter test args...]
# Example: run_d3_device.sh run3 --plain-name P2GC-3
set -u
cd "$(dirname "$0")/.."

RUN="$1"; shift
LOG="docs/evidence_p2gc_d3_${RUN}_$(date +%Y-%m-%d).log"

export ANDROID_SDK_ROOT="C:\\Users\\PORTCR\\AppData\\Local\\Android\\Sdk"
export PATH="/c/Users/PORTCR/AppData/Local/Android/Sdk/platform-tools:/h/flutter/bin:$PATH"

echo "=== D-3 device run: $RUN === $(date)" >> "$LOG"
flutter test integration_test/phase2gc_device_verification_test.dart \
  -d R83L20FRDFM \
  --dart-define=P2GC_TEST_URL=http://192.168.29.246:8712/test.mp4 \
  "$@" >> "$LOG" 2>&1
echo "=== exit=$? === $(date)" >> "$LOG"
tail -2 "$LOG"