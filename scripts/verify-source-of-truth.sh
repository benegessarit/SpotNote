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

reject_grep() {
  local needle="$1"
  local file="$2"
  if /usr/bin/grep -F -- "$needle" "$ROOT/$file" >/dev/null; then
    fail "retired SpotNote contract '$needle' still present in $file"
  fi
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
require_file "Sources/Spotlight/MarkdownOutline.swift"
require_file "Sources/Spotlight/Resources/HermesLogo.png"
require_file "Sources/Spotlight/Resources/IBMPlexMono-Regular.ttf"
require_file "Tests/SpotlightTests/ScratchpadHandoffTests.swift"
require_file "Tests/SpotlightTests/MultilineEditorOutlineTests.swift"
require_file "Tests/SpotlightTests/SpotlightWindowControllerTests.swift"
require_file "scripts/launch-contract-smoke.py"
require_file "scripts/headless-smoke.sh"

[[ ! -e "$ROOT/Sources/Spotlight/VimStatusLine.swift" ]] || fail "statusline source still exists"
if /usr/bin/grep -R -F -- "vimBarHeight" "$ROOT/Sources" "$ROOT/Tests" >/dev/null; then
  fail "statusline height constant still referenced"
fi
for retired_tray_contract in \
  "Open Tray / hide HUD" \
  "openTray" \
  "handleTrayHotkey" \
  "toggleVaultState" \
  "Dump a thought"; do
  if /usr/bin/grep -R -F -- "$retired_tray_contract" "$ROOT/Sources" "$ROOT/Tests" >/dev/null; then
    fail "retired tray contract '$retired_tray_contract' still present in source/tests"
  fi
done
if /usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$ROOT/App/Info.plist" 2>/dev/null | /usr/bin/grep -F -- "true" >/dev/null; then
  fail "source Info.plist still sets LSUIElement=true; LaunchServices opens it as an invisible background status item"
fi
require_grep "catppuccin-frappe" "Sources/Spotlight/Theme.swift"
require_grep "rose-pine-moonlight" "Sources/Spotlight/Theme.swift"
require_grep "dracula" "Sources/Spotlight/Theme.swift"
require_grep "ScratchpadHandoffClient" "Sources/Spotlight/ScratchpadHandoff.swift"
require_grep "Sending to Linear" "Sources/Spotlight/MultilineEditor.swift"
require_grep "Created \(identifier) in Linear" "Sources/Spotlight/ScratchpadHandoff.swift"
reject_grep "Sent to Hermes for Linear" "Sources/Spotlight/MultilineEditor.swift"
require_grep "defaultHUDOriginHugsRightEdge" "Tests/SpotlightTests/SpotlightWindowControllerTests.swift"
require_grep "defaultHUDOriginHugsBottomEdge" "Tests/SpotlightTests/SpotlightWindowControllerTests.swift"
require_grep "defaultEdgeInset: CGFloat =" "Sources/Spotlight/SpotlightWindow.swift"
require_grep "hugs the right edge" "Tests/SpotlightTests/SpotlightWindowControllerTests.swift"
require_grep "bottom-right corner" "AGENTS.md"
require_grep "leadingInset: CGFloat = 0" "Sources/Spotlight/EditorMetrics.swift"
require_grep "textLeadingGap: CGFloat = 37" "Sources/Spotlight/EditorMetrics.swift"
require_grep "fontSize: CGFloat = 20" "Sources/Spotlight/EditorMetrics.swift"
require_grep "systemFont" "Sources/Spotlight/SpotNoteFont.swift"
require_grep "SpotNoteFont.editor()" "Sources/Spotlight/SpotlightRootView.swift"
require_grep "continuationPrefix" "Sources/Spotlight/MarkdownOutline.swift"
require_grep "normal-mode o under a bullet opens a matching bullet below" "Tests/SpotlightTests/MultilineEditorOutlineTests.swift"
reject_grep "uncheckedLineMarkerGlyph" "Sources/Spotlight/LineNumberRuler.swift"
reject_grep "checkedLineMarkerGlyph" "Sources/Spotlight/LineNumberRuler.swift"
reject_grep "lineMarkerRightNudge" "Sources/Spotlight/LineNumberRulerMarkers.swift"
require_grep "the gutter is zero-width whenever line-flash hints are not showing" "Tests/SpotlightTests/LineNumberRulerTests.swift"
reject_grep "showLineNumbers" "Sources/Spotlight/ThemePreferences.swift"
# Raycast leaves the editor undimmed with a menu open (probed 2026-08-09).
reject_grep "RaycastModalPalette.backdrop" "Sources/Spotlight/SpotlightRootView.swift"
# Sheet translucency is MEASURED (2026-08-09 swatch-lab): .popover under
# the 0.45 ink matches Raycast's ~21% backdrop bleed; .menu at 0.90
# matched the composite color but transmitted ~0 (visibly flat).
require_grep "SpotNoteVisualEffectView(material: .popover, blendingMode: .behindWindow)" "Sources/Spotlight/RaycastModals.swift"
# Menu polish round 2 (probed 2026-08-09 same-scale captures): group gaps
# are pure whitespace (no hairline) and the pill + is drawn at 2pt, not
# the heavier-stroke raster.
reject_grep "sectionRule" "Sources/Spotlight/RaycastActionsModal.swift"
# The actions sheet hugs its content (computed listHeight, NO height
# cap -- a 400pt cap hid Show Sidebar/Change Theme below the fold while
# the live menu shows its whole list) and draws the probed hairline
# under its search field; the lights are hover-gated but the pill is not
# (David 2026-08-10).
require_grep "frame(height: listHeight)" "Sources/Spotlight/RaycastActionsModal.swift"
require_grep "searchDivider" "Sources/Spotlight/RaycastActionsModal.swift"
require_grep "showsLights: windowHovered || anyModalShown" "Sources/Spotlight/SpotlightRootView.swift"
# Pill icon hover is a CIRCLE at a bare +8 RGB, not a rounded rect
# (probed on David's 2026-08-10 Raycast hover capture).
require_grep "Circle()" "Sources/Spotlight/RaycastChrome.swift"
# Editor hint labels are bare colored letters (nvim hl_mode "replace"
# look) -- the opaque pink pills were retired 2026-08-10; hop_red is the
# love-toward-red blend, never bare love.
require_grep "drawHintLabel" "Sources/Spotlight/MultilineEditorWordHint.swift"
reject_grep "drawHintChip" "Sources/Spotlight/MultilineEditorFlashRendering.swift"
reject_grep "0xEB" "Sources/Spotlight/MultilineEditorWordHint.swift"
reject_grep "sectionRule" "Sources/Spotlight/RaycastModals.swift"
require_grep "RaycastPlusShape" "Sources/Spotlight/RaycastChrome.swift"
# The sidebar is a SHELF child panel with its own height; the window
# never widens (the retired width-widening path must stay dead).
reject_grep "expectedPanelWidth" "Sources/Spotlight/SpotlightWindow.swift"
require_grep "sidebarShelfHeight" "Sources/Spotlight/SpotlightWindow.swift"
require_grep "task editor keeps restored breathing room before text" "Tests/SpotlightTests/EditorMetricsTests.swift"
require_grep "sendCurrentTaskToLinear" "Sources/Spotlight/MultilineEditor.swift"
require_grep "case planned = \"Planned\"" "Sources/Spotlight/ScratchpadHandoff.swift"
require_grep "case started = \"Started\"" "Sources/Spotlight/ScratchpadHandoff.swift"
require_grep "case later = \"Later\"" "Sources/Spotlight/ScratchpadHandoff.swift"
require_grep "dueDate" "Sources/Spotlight/ScratchpadHandoff.swift"
require_grep "g-status motions send the current bullet to Linear" "Tests/SpotlightTests/VimEngineTests.swift"
require_grep "status Linear handoff sends the current bullet block with labels and due date" "Tests/SpotlightTests/MultilineEditorLinearTaskMotionTests.swift"
require_grep "gc sends the current bullet to the Code workspace at Triage" "Tests/SpotlightTests/VimEngineTests.swift"
require_grep "case code" "Sources/Spotlight/ScratchpadHandoff.swift"
require_file "Sources/Spotlight/SpotNoteFormatter.swift"
require_grep "static func normalize" "Sources/Spotlight/SpotNoteFormatter.swift"
require_grep "case normalizeDocument" "Sources/Spotlight/VimEngine.swift"
require_grep "gg scrolls the document start to the top" "Tests/SpotlightTests/MultilineEditorVimMotionTests.swift"
require_grep "roomyVisibleLinesFloor = 1" "Sources/Spotlight/EditorMetrics.swift"
require_grep "appendCurrentLineToTrayNote" "Sources/Spotlight/VimEngine.swift"
require_grep "jumpToToDoSection" "Sources/Spotlight/VimEngine.swift"
require_grep "## Todo" "Sources/Spotlight/SpotNoteSectionHeadings.swift"
require_grep "## Tray" "Sources/Spotlight/SpotNoteSectionHeadings.swift"
reject_grep "jumpToHabitsSection" "Sources/Spotlight/VimEngine.swift"
reject_grep "jumpToBigThingsSection" "Sources/Spotlight/VimEngine.swift"
reject_grep "## Habits" "Sources/Spotlight/SpotNoteSectionHeadings.swift"
reject_grep "## Big Things" "Sources/Spotlight/SpotNoteSectionHeadings.swift"
reject_grep ",h jumps to" "Tests/SpotlightTests/VimEngineTests.swift"
reject_grep ",b jumps to" "Tests/SpotlightTests/VimEngineTests.swift"
require_grep ",d jumps to the Todo section" "Tests/SpotlightTests/VimEngineTests.swift"
require_grep "gT ignores internal Tray blank lines" "Tests/SpotlightTests/MultilineEditorVimMotionTests.swift"
require_grep "Captures/Trays/spotnote-tray.md" "Sources/Spotlight/TrayNoteDestination.swift"
require_grep "appendCurrentLineToStateNote" "Sources/Spotlight/VimEngine.swift"
require_grep "Work/hermes-build/Notes/State.md" "Sources/Spotlight/StateNoteDestination.swift"
require_grep "tray has no separate global open shortcut" "Tests/SpotlightTests/ShortcutStoreTests.swift"
require_grep "SPOTNOTE_HEADLESS_TEST" "Sources/SpotNoteApp/AppDelegate.swift"
require_grep "SPOTNOTE_HEADLESS_TEST=1" "scripts/headless-smoke.sh"
require_grep "SPOTNOTE_FINAL_LAUNCH_MODE" "scripts/install-release.sh"
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
  IBM_PLEX_MONO="$RESOURCE_BUNDLE/Resources/IBMPlexMono-Regular.ttf"
  [[ -x "$BIN" ]] || fail "installed SpotNote binary missing: $BIN"
  [[ -d "$RESOURCE_BUNDLE" ]] || fail "installed resource bundle missing: $RESOURCE_BUNDLE"
  [[ -f "$HERMES_LOGO" ]] || fail "installed Hermes logo missing: $HERMES_LOGO"
  [[ -f "$IBM_PLEX_MONO" ]] || fail "installed IBM Plex Mono resource missing: $IBM_PLEX_MONO"
  STRINGS="$(/usr/bin/strings "$BIN")"
  for needle in \
    "catppuccin-frappe" \
    "rose-pine-moonlight" \
    "ScratchpadHandoffClient" \
    "Sending to Linear"; do
    /usr/bin/grep -F -- "$needle" <<<"$STRINGS" >/dev/null || fail "installed binary missing string: $needle"
  done
  if /usr/bin/grep -F -- "Sent to Hermes for Linear" <<<"$STRINGS" >/dev/null; then
    fail "installed binary still contains retired Linear handoff toast wording"
  fi
  if /usr/bin/grep -F -- "VimStatusLine" <<<"$STRINGS" >/dev/null; then
    fail "installed binary still contains VimStatusLine"
  fi
  for retired_tray_contract in \
    "Open Tray / hide HUD" \
    "openTray" \
    "handleTrayHotkey" \
    "toggleVaultState" \
    "Dump a thought"; do
    if /usr/bin/grep -F -- "$retired_tray_contract" <<<"$STRINGS" >/dev/null; then
      fail "installed binary still contains retired tray contract: $retired_tray_contract"
    fi
  done
  /usr/bin/grep -F -- "Sent to spotnote-tray.md" <<<"$STRINGS" >/dev/null \
    || fail "installed binary missing spotnote-tray.md append confirmation string"
  if /usr/bin/grep -F -- "## Habits" <<<"$STRINGS" >/dev/null; then
    fail "installed binary still contains retired Habits heading contract string"
  fi
  if /usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist" 2>/dev/null | /usr/bin/grep -F -- "true" >/dev/null; then
    fail "installed app still sets LSUIElement=true; LaunchServices will open it as an invisible background status item"
  fi
  /usr/bin/codesign --verify --deep --strict "$APP"
  printf 'OK: installed app fingerprints and codesign verified\n'
fi
