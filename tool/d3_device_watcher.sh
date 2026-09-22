#!/usr/bin/env bash
# D-3 device-state watcher: logs app PID + power state every 5 seconds.
# Usage: d3_device_watcher.sh <run-name>
set -u
RUN="$1"
LOG="docs/evidence_p2gc_d3_watcher_${RUN}_2026-09-22.log"
PKG="net.specta.app"
count=0
{
  echo "=== watcher start $(date) ==="
  while true; do
    pid=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
    wake=$(adb shell dumpsys power 2>/dev/null | grep -o "mWakefulness=[A-Za-z]*" | head -1)
    disp=$(adb shell dumpsys power 2>/dev/null | grep -o "mHoldingDisplaySuspendBlocker=true" | head -1)
    echo "$(date +%H:%M:%S) pid=${pid:-NONE} ${wake:-} ${disp:-}"
    if [ -z "$pid" ]; then
      count=$((count + 1))
      [ "$count" -ge 6 ] && { echo "=== watcher end: app absent 30s, stopping $(date) ==="; break; }
    else
      count=0
    fi
    sleep 5
  done
} >> "$LOG" 2>&1
