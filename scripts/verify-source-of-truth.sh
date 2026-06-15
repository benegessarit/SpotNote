#!/usr/bin/env bash
# Verify this checkout is the stable SpotNote source and still carries David's custom app contract.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_ROOT="/Users/davidbeyer/Projects/SpotNote"
CHECK_INSTALLED=0
if [[ "${1:-}" == "--installed" ]]; then
  CHECK_INSTALLED=1
fi

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "missing required file: $1"
}

require_grep() {
  local needle="$1"
  local file="$2"
  /usr/bin/grep -F -- "$needle" "$ROOT/$file" >/dev/null || fail "missing '$needle' in $file"
}

case "$ROOT" in
  *'/.hermes/kanban/'*|*'/.paperclip-'*|'/tmp/'*|'/private/tmp/'*)
    fail "refusing disposable SpotNote source root: $ROOT"
    ;;
esac

if [[ "$ROOT" != "$EXPECTED_ROOT" && "${SPOTNOTE_ALLOW_NONSTANDARD_ROOT:-0}" != "1" ]]; then
  fail "expected stable root $EXPECTED_ROOT, got $ROOT"
fi

GIT_ROOT="$(/usr/bin/git -C "$ROOT" rev-parse --show-toplevel)"
[[ "$GIT_ROOT" == "$ROOT" ]] || fail "git root mismatch: $GIT_ROOT"

require_file "Package.swift"
require_file "Sources/Spotlight/Theme.swift"
require_file "Sources/Spotlight/ScratchpadHandoff.swift"
require_file "Sources/Spotlight/HermesToastView.swift"
require_file "Sources/Spotlight/Resources/HermesLogo.png"
require_file "Tests/SpotlightTests/ScratchpadHandoffTests.swift"
require_file "Tests/SpotlightTests/SpotlightWindowControllerTests.swift"
require_file "scripts/launch-contract-smoke.py"

[[ ! -e "$ROOT/Sources/Spotlight/VimStatusLine.swift" ]] || fail "statusline source still exists"
if /usr/bin/grep -R -F -- "vimBarHeight" "$ROOT/Sources" "$ROOT/Tests" >/dev/null; then
  fail "statusline height constant still referenced"
fi
if /usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$ROOT/App/Info.plist" 2>/dev/null | /usr/bin/grep -F -- "true" >/dev/null; then
  fail "source Info.plist still sets LSUIElement=true; LaunchServices opens it as an invisible background status item"
fi
require_grep "catppuccin-frappe" "Sources/Spotlight/Theme.swift"
require_grep "rose-pine-moonlight" "Sources/Spotlight/Theme.swift"
require_grep "ScratchpadHandoffClient" "Sources/Spotlight/ScratchpadHandoff.swift"
require_grep "Sending to Linear" "Sources/Spotlight/MultilineEditor.swift"
require_grep "Linear task created" "Sources/Spotlight/MultilineEditor.swift"
require_grep "rightwardTravel * 0.30" "Tests/SpotlightTests/SpotlightWindowControllerTests.swift"
python3 "$ROOT/scripts/launch-contract-smoke.py" >/dev/null

printf 'OK: stable source root %s\n' "$ROOT"
printf 'OK: custom source fingerprints present\n'
printf 'Git: %s\n' "$(/usr/bin/git -C "$ROOT" rev-parse --short HEAD)"
if [[ -n "$(/usr/bin/git -C "$ROOT" status --porcelain=v1 -uall)" ]]; then
  printf 'WARN: working tree has uncommitted changes\n'
else
  printf 'OK: working tree clean\n'
fi

if [[ "$CHECK_INSTALLED" == "1" ]]; then
  APP="/Applications/SpotNote.app"
  BIN="$APP/Contents/MacOS/SpotNote"
  RESOURCE_BUNDLE="$APP/Contents/Resources/SpotNote_Spotlight.bundle"
  HERMES_LOGO="$RESOURCE_BUNDLE/Resources/HermesLogo.png"
  [[ -x "$BIN" ]] || fail "installed SpotNote binary missing: $BIN"
  [[ -d "$RESOURCE_BUNDLE" ]] || fail "installed resource bundle missing: $RESOURCE_BUNDLE"
  [[ -f "$HERMES_LOGO" ]] || fail "installed Hermes logo missing: $HERMES_LOGO"
  STRINGS="$(/usr/bin/strings "$BIN")"
  for needle in \
    "catppuccin-frappe" \
    "rose-pine-moonlight" \
    "ScratchpadHandoffClient" \
    "Sending to Linear" \
    "Linear task created"; do
    /usr/bin/grep -F -- "$needle" <<<"$STRINGS" >/dev/null || fail "installed binary missing string: $needle"
  done
  if /usr/bin/grep -F -- "VimStatusLine" <<<"$STRINGS" >/dev/null; then
    fail "installed binary still contains VimStatusLine"
  fi
  if /usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist" 2>/dev/null | /usr/bin/grep -F -- "true" >/dev/null; then
    fail "installed app still sets LSUIElement=true; LaunchServices will open it as an invisible background status item"
  fi
  /usr/bin/codesign --verify --deep --strict "$APP"
  printf 'OK: installed app fingerprints and codesign verified\n'
fi
