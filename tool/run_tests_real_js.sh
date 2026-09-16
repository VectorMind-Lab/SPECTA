#!/usr/bin/env bash
# Runs the SPECTA test suite with the flutter_js QuickJS bridge reachable, so the
# real-engine sandbox tests in
# test/core/extensions/runtime/flutter_js_sandbox_test.dart actually execute.
#
# Why this is needed
# ------------------
# flutter_js bundles `quickjs_c_bridge.dll` inside the pub cache under
# `flutter_js-<version>/windows/shared`. The plugin resolves it with
# `DynamicLibrary.open('quickjs_c_bridge.dll')`, which only searches the loader
# path. Under `flutter test` on Windows that directory is not on the path, so the
# engine cannot be loaded and the real-engine group is SKIPPED.
#
# On Android the same native library ships inside the APK, so no script is
# required there — but a device or emulator is.
#
# Usage
# -----
#   tool/run_tests_real_js.sh                 # full suite, real engine active
#   tool/run_tests_real_js.sh <path> [more]   # only the named test files
#
# A skipped real-engine group is always reported as skipped; it is never
# reported as passing.

set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

# Locate the pub cache.
PUB_CACHE_DIR="${PUB_CACHE:-}"
if [ -z "$PUB_CACHE_DIR" ]; then
  if [ -d "$HOME/AppData/Local/Pub/Cache" ]; then
    PUB_CACHE_DIR="$HOME/AppData/Local/Pub/Cache"   # Windows default
  else
    PUB_CACHE_DIR="$HOME/.pub-cache"                # Linux/macOS default
  fi
fi

if [ ! -d "$PUB_CACHE_DIR" ]; then
  echo "error: pub cache not found at $PUB_CACHE_DIR" >&2
  echo "       set PUB_CACHE to override." >&2
  exit 1
fi

# Newest cached flutter_js wins, matching what pub resolves.
FLUTTER_JS_DIR=$(find "$PUB_CACHE_DIR/hosted" -maxdepth 3 -type d -name 'flutter_js-*' 2>/dev/null | sort | tail -1 || true)
if [ -z "$FLUTTER_JS_DIR" ]; then
  echo "error: no cached flutter_js package found under $PUB_CACHE_DIR/hosted" >&2
  echo "       run 'flutter pub get' first." >&2
  exit 1
fi

SHARED_DIR="$FLUTTER_JS_DIR/windows/shared"
if [ ! -f "$SHARED_DIR/quickjs_c_bridge.dll" ]; then
  echo "error: quickjs_c_bridge.dll not found in $SHARED_DIR" >&2
  exit 1
fi

# MSYS/Cygwin need a Windows-style path; a native shell wants the plain one.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    SHARED_ON_PATH=$(cygpath -w "$SHARED_DIR" 2>/dev/null || echo "$SHARED_DIR")
    ;;
  *)
    SHARED_ON_PATH="$SHARED_DIR"
    ;;
esac

export PATH="$SHARED_ON_PATH:$PATH"

echo "flutter_js : $FLUTTER_JS_DIR"
echo "bridge dir : $SHARED_ON_PATH"
echo

if [ "$#" -gt 0 ]; then
  exec "$FLUTTER_BIN" test "$@"
fi

exec "$FLUTTER_BIN" test
