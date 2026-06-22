#!/usr/bin/env bash
# Build/launch SpotNote without surfacing HUD or stealing focus, then verify
# the process is alive and owns no visible windows. Use this for agent/CI
# launch smokes instead of opening the HUD on David's active Space.
# Usage: ./scripts/headless-smoke.sh [debug|release|--installed]
set -euo pipefail

MODE="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/build"
LOG="$LOG_DIR/headless-smoke.log"
PID_FILE="$LOG_DIR/headless-smoke.pid"

if [[ "$MODE" == "--installed" ]]; then
  APP="/Applications/SpotNote.app"
else
  "$ROOT/scripts/build.sh" "$MODE"
  APP="$ROOT/build/SpotNote.app"
fi

BIN="$APP/Contents/MacOS/SpotNote"
[[ -x "$BIN" ]] || { echo "FAIL: executable missing: $BIN" >&2; exit 1; }

mkdir -p "$LOG_DIR"
rm -f "$LOG" "$PID_FILE"

SPOTNOTE_HEADLESS_TEST=1 "$BIN" >"$LOG" 2>&1 &
PID=$!
printf '%s\n' "$PID" >"$PID_FILE"

cleanup() {
  if /bin/ps -p "$PID" >/dev/null 2>&1; then
    /bin/kill "$PID" >/dev/null 2>&1 || true
    wait "$PID" 2>/dev/null || true
    /bin/sleep 0.2
    if /bin/ps -p "$PID" >/dev/null 2>&1; then
      /bin/kill -9 "$PID" >/dev/null 2>&1 || true
      wait "$PID" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT

for _ in {1..30}; do
  if /usr/bin/grep -Fq "SpotNote headless test launch ready" "$LOG" 2>/dev/null; then
    break
  fi
  if ! /bin/ps -p "$PID" >/dev/null 2>&1; then
    echo "FAIL: SpotNote exited before headless readiness" >&2
    cat "$LOG" >&2 || true
    exit 1
  fi
  sleep 0.1
done

/usr/bin/grep -Fq "SpotNote headless test launch ready" "$LOG" || {
  echo "FAIL: headless readiness marker missing" >&2
  cat "$LOG" >&2 || true
  exit 1
}

/usr/bin/python3 - "$PID" <<'PY'
import sys
import Quartz

pid = int(sys.argv[1])
windows = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID) or []
spotnote_windows = [
    window for window in windows
    if window.get("kCGWindowOwnerPID") == pid
    and window.get("kCGWindowAlpha", 1) > 0
    and window.get("kCGWindowBounds", {}).get("Width", 0) > 1
    and window.get("kCGWindowBounds", {}).get("Height", 0) > 1
]
if spotnote_windows:
    print("FAIL: headless launch created visible SpotNote windows", file=sys.stderr)
    for window in spotnote_windows:
        print(window, file=sys.stderr)
    raise SystemExit(1)
print("OK: headless launch has no visible SpotNote windows")
PY

printf 'OK: SpotNote headless smoke passed pid=%s app=%s log=%s\n' "$PID" "$APP" "$LOG"
