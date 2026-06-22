#!/usr/bin/env bash
# Build then launch SpotNote.app.
# Usage: ./scripts/run.sh [debug|release] [--headless]   (default: debug)
set -euo pipefail

CONFIG="${1:-debug}"
MODE="${2:-normal}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$CONFIG" == "--headless" ]]; then
  CONFIG="debug"
  MODE="--headless"
fi

if [[ "$MODE" == "--headless" || "$MODE" == "headless" ]]; then
  exec "$ROOT/scripts/headless-smoke.sh" "$CONFIG"
fi

"$ROOT/scripts/build.sh" "$CONFIG"

APP="$ROOT/build/SpotNote.app"

# Kill any previous instance so hotkey registration doesn't collide.
pkill -x SpotNote 2>/dev/null || true

echo "==> opening $APP"
open "$APP"
echo "Press ⌘⇧Space to toggle SpotNote."
