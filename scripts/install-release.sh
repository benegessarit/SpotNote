#!/usr/bin/env bash
# Build, back up, install, and verify SpotNote from the stable project repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_ROOT="/Users/davidbeyer/Projects/SpotNote"
APP="/Applications/SpotNote.app"
BUILT_APP="$ROOT/build/SpotNote.app"
BACKUP_DIR="/Users/davidbeyer/Library/Application Support/SpotNote/AppBackups"
STAMP="$(/bin/date -u +%Y%m%dT%H%M%SZ)"
BACKUP_APP="$BACKUP_DIR/SpotNote-pre-install-$STAMP.app"
RESTORE_ON_FAILURE=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

restore_backup_on_failure() {
  local status=$?
  if [[ "$status" -ne 0 && "$RESTORE_ON_FAILURE" == "1" && -d "$BACKUP_APP" ]]; then
    printf 'Install failed; restoring backup %s\n' "$BACKUP_APP" >&2
    rm -rf "$APP"
    /usr/bin/ditto "$BACKUP_APP" "$APP"
  fi
  exit "$status"
}

trap restore_backup_on_failure EXIT

case "$ROOT" in
  *'/.hermes/kanban/'*|*'/.paperclip-'*|'/tmp/'*|'/private/tmp/'*)
    fail "refusing to install from disposable source root: $ROOT"
    ;;
esac

if [[ "$ROOT" != "$EXPECTED_ROOT" && "${SPOTNOTE_ALLOW_NONSTANDARD_ROOT:-0}" != "1" ]]; then
  fail "expected stable root $EXPECTED_ROOT, got $ROOT"
fi

GIT_ROOT="$(/usr/bin/git -C "$ROOT" rev-parse --show-toplevel)"
[[ "$GIT_ROOT" == "$ROOT" ]] || fail "git root mismatch: $GIT_ROOT"

if [[ -n "$(/usr/bin/git -C "$ROOT" status --porcelain=v1 -uall)" && "${SPOTNOTE_ALLOW_DIRTY_INSTALL:-0}" != "1" ]]; then
  /usr/bin/git -C "$ROOT" status --short -uall >&2
  fail "working tree is dirty; commit or set SPOTNOTE_ALLOW_DIRTY_INSTALL=1 for a named visual trial"
fi

"$ROOT/scripts/verify-source-of-truth.sh"
"$ROOT/scripts/build.sh" release
[[ -d "$BUILT_APP" ]] || fail "release build did not create $BUILT_APP"

/bin/mkdir -p "$BACKUP_DIR"
if [[ -d "$APP" ]]; then
  /usr/bin/ditto "$APP" "$BACKUP_APP"
  RESTORE_ON_FAILURE=1
  printf 'Backup: %s\n' "$BACKUP_APP"
fi

/usr/bin/osascript -e 'tell application "SpotNote" to quit' >/dev/null 2>&1 || true
/bin/sleep 1
rm -rf "$APP"
/usr/bin/ditto "$BUILT_APP" "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
"$ROOT/scripts/verify-source-of-truth.sh" --installed
RESTORE_ON_FAILURE=0
/usr/bin/open -a "$APP"
printf 'OK: installed and launched %s from %s\n' "$APP" "$ROOT"
