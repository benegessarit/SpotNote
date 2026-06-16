---
type: Plan
status: Completed
created: 2026-06-15
parent: standalone
---

# SpotNote two-flow + wider checkbox plan

## Goal

Make SpotNote feel like a tiny native note capture surface with two clear modes:

1. **Task flow** — the existing fast task lane that turns selected/current lines into Linear tasks through local ingress.
2. **Daily note flow** — a vault-backed lane that appends note text to today's Markdown daily note, so writing in SpotNote feels like writing in the same daily note David would edit from Neovim.

Also fix the visual mismatch where the unchecked marker `[ ]` looks narrower than the checked marker `[ x ]`.

## Implementation result

Implemented 2026-06-15 as the append-only MVP:

- Canonical unchecked marker is `[   ]`; legacy `[ ]`, `[x]`, and `[ x ]` remain accepted.
- `gd` / counted `gd` appends current or counted lines to today's Daily Note and clears the original SpotNote lines only after the durable append succeeds and the original range is unchanged.
- `⌘⌥D` is the default Daily Note shortcut for new installs; older custom maps that already own `⌘⌥D` preserve the user's binding and backfill Daily Note to `⌘⌥⇧D`.
- Daily Note writes use `/Users/davidbeyer/Documents/knowledge/Daily/YYYY/MM-DD-YYYY.md`, create missing files with minimal Daily frontmatter, append only, preserve existing frontmatter/title, and preserve meaningful indentation.
- No statusline, no live Daily buffer, no file watcher, and no broad plugin abstraction were added.

## Current code map

- `Sources/Spotlight/MultilineEditor.swift`
  - Owns special token expansion, checklist marker matching/toggling, line extraction, and the current `sendCurrentLinesToLinear(_:)` success-before-delete pattern.
  - Canonical unchecked marker is `[   ]`; checked marker is `[ x ]`; legacy `[ ]` remains accepted.
- `Sources/Spotlight/ScratchpadHandoff.swift`
  - Owns Linear payload creation and title normalization.
  - This should stay task-specific.
- `Sources/Spotlight/ChatSession.swift` + `Sources/Core/ChatStore.swift`
  - Own the local SpotNote scratch-note library.
  - This should remain useful as local draft/session state, not become the daily-note writer directly.
- `Sources/Spotlight/SpotlightRootView.swift` + `Sources/Spotlight/SpotlightWindow.swift`
  - Own the HUD view/controller seams and the closure passed into the editor for Linear handoff.
- `Sources/Spotlight/VimEngine.swift` + `Sources/Spotlight/MultilineEditorVim.swift`
  - Own Vim normal-mode actions. `gl` already sends counted/current lines to Linear.
- `Sources/Spotlight/Shortcut.swift` + `ShortcutsSettings.swift`
  - Own customizable keyboard action labels/defaults/settings.
- Daily-note convention lives in `/Users/davidbeyer/Documents/knowledge/Daily/AGENTS.md`:
  - Path shape: `Daily/<year>/<MM-DD-YYYY>.md`.
  - Minimal frontmatter: `type: daily`, `created: YYYY-MM-DD`.
  - Agents/app should append only when explicitly requested; no split/rename/normalize/backfill.

## Product decision

Do **not** make two separate apps or two unrelated storage systems. The implemented MVP keeps one editor surface and adds one explicit destination action: Linear remains `gl` / `⌘⌥L`; Daily Note append is `gd` / `⌘⌥D`.

Plain-language model: SpotNote is still one HUD. Scratch text stays local while drafting; an explicit command commits the selected/current lines to either the task inbox or today's Daily Note. A persistent flow mode enum can wait until there is real evidence that append commands are not enough.

## Phase 1 — checkbox width fix

### Desired behavior

- The unchecked default marker should visually line up with `[ x ]`.
- Use `[   ] ` as the canonical unchecked marker instead of `[ ] `.
- Continue accepting legacy `[ ]` and `[x]` / `[ x ]`.
- Toggle cycle becomes:
  - `[   ] item` -> `[ x ] item` -> `item`
  - legacy `[ ] item` -> `[ x ] item` -> `item`
  - legacy `[x] item` displays/toggles as `[ x ] item`

### Code shape

In `ChecklistMarker`:

- Make `.unchecked` canonical text `[   ]`.
- Keep the matcher lenient enough to recognize:
  - `\[\s*\]` as unchecked, including legacy `[ ]`.
  - `\[\s*[xX]\s*\]` as checked, including `[x]`, `[ x ]`, `[ X ]`.
- Keep `ensureTrailingSpace` behavior so a marker at the start of text becomes `[   ] item`, not `[   ]item`.

### Tests

Update/add tests in `MultilineEditorTokenTests.swift`:

- `@cl` expands to `[   ] `.
- Return after `@cl` preserves `[   ] \n`.
- Backspace/undo expectations account for `[   ]`.
- Toggle from plain line inserts `[   ] ` and moves caret by the new marker length.
- Toggle from `[   ]` produces `[ x ]`.
- Toggle from legacy `[ ]` also produces `[ x ]`.
- Toggle from `[x]` still normalizes safely.

Update `ShortcutStoreTests.swift` help text assertion to expect the visible default marker `[   ]`, not `[ ]`.

## Phase 2 — daily-note path and writer, isolated from UI

Create a tiny, testable daily-note service. Suggested new file:

- `Sources/Spotlight/DailyNoteDestination.swift`

Core types:

```swift
struct DailyNotePathResolver: Sendable {
  let vaultRoot: URL
  let calendar: Calendar
  let timeZone: TimeZone
  func url(for date: Date) -> URL
}

actor DailyNoteWriter {
  func ensureDailyNote(for date: Date) throws -> URL
  func append(_ text: String, toDailyNoteFor date: Date) throws -> URL
}
```

Rules:

- Default vault root: `/Users/davidbeyer/Documents/knowledge`.
- Daily note path: `Daily/yyyy/MM-dd-yyyy.md`.
- If today's file is missing, create it with:

```markdown
---
type: daily
created: YYYY-MM-DD
---

# EEEE, MMMM d, yyyy

```

- Append only; never rewrite old text.
- Normalize appended text minimally:
  - Trim only surrounding blank lines from the payload.
  - Ensure exactly one blank line before the appended block if the file already has content.
  - Add trailing newline at EOF.
- Do not add noisy agent metadata into the daily note.
- Do not change existing frontmatter/title if the file already exists, even if it is imperfect.

This keeps the daily-note lane professional: small, local, deterministic, unit-testable, and not coupled to SwiftUI or `NSTextView`.

## Phase 3 — generalize editor commit actions without making it abstract soup

Current editor has a specific closure:

```swift
var onSendLinearTask: ((String) async throws -> Void)?
```

Do not replace this with a broad plugin system. Add one sibling closure first:

```swift
var onAppendDailyNote: ((String) async throws -> URL)?
```

Then extract the repeated line-selection + commit-success-before-delete pattern into a small helper inside `PlaceholderTextView`:

```swift
private func commitSelectedLines(
  count: Int,
  preparing payload: (String) -> String?,
  unavailableMessage: String,
  progressMessage: String,
  successMessage: String,
  commit: @escaping (String) async throws -> Void
)
```

Use it for both:

- `sendCurrentLinesToLinear(_:)`
- `appendCurrentLinesToDailyNote(_:)`

Important behavior:

- Extract current/counted lines.
- Prepare/normalize payload.
- Show progress message.
- Run async commit.
- Delete original lines **only if** the committed text range is unchanged.
- If the text changed during the async write, do not delete; show “Daily note updated; line changed” / “Linear created; line changed.”

This preserves the strong safety pattern already in `sendCurrentLinesToLinear(_:)`.

## Phase 4 — shortcuts and Vim surface

Keep task and note flows visibly separate.

### Existing task actions stay

- Normal mode: `gl` sends current/counted lines to Linear.
- Shortcut: `⌘⌥L` sends current line to Linear.

### Add daily-note actions

Add to `ShortcutAction`:

```swift
case appendToDailyNote
```

Suggested defaults:

- `appendToDailyNote`: `⌘⌥D`
- If an existing customized shortcut map already owns `⌘⌥D`, preserve that user binding and backfill Daily Note to `⌘⌥⇧D`.

Add to Vim engine:

- `gd` = append current/counted lines to today's daily note.

Why `gd`: it mirrors `gl` without stealing the Linear muscle memory. “g + destination letter” becomes the mini-language.

Add command-palette entries via existing `ShortcutAction.allCases` path automatically, but make names/subtitles plain:

- “Append line to Daily Note” — “Append current/counted lines to today's vault daily note, then remove them from SpotNote after a successful write.”
Opening today's Daily Note in Neovim/editor is intentionally out of scope for this pass.

## Phase 5 — flow indicator, not statusline

Do not bring back a statusline.

Add a tiny, beautiful flow affordance only if needed:

- A subtle top-right or placeholder-level pill: `Task` / `Daily`.
- Or no persistent chrome at all: use command feedback only (“Daily note updated”).

Recommendation for first pass: **no persistent pill**. Keep the HUD clean. Use messages for actions and maybe placeholder copy:

- Task/default placeholder: `Jot something down…`
- Daily placeholder if/when explicitly in daily mode: `Write to today’s daily note…`

If we add a persistent mode switch later, keep it keyboard-first and tiny:

- `⌘1` Task
- `⌘2` Daily
- show only while switching or when command palette is open.

## Phase 6 — optional true “daily editing mode”

The first implementation should append selected/current lines to the daily note. That is reliable and low-risk.

A heavier “live daily buffer” can come later if the append lane feels too limited:

- Load today's daily note into the editor when flow = `.dailyNote`.
- Autosave every edit directly to the Markdown file.
- Watch for external file changes from Neovim and reconcile.

Do **not** start there. Live shared editing introduces file-watcher/race/merge complexity. The MVP should prove the core feeling with append-on-command first.

## Test plan

Unit tests:

- `DailyNotePathResolverTests`
  - `2026-06-15` -> `Daily/2026/06-15-2026.md`.
- `DailyNoteWriterTests`
  - creates missing daily note with minimal frontmatter/title.
  - appends with stable blank-line behavior.
  - preserves existing file content/frontmatter exactly before append.
  - writes a final newline.
- `MultilineEditorTokenTests`
  - `[   ]` token/toggle/caret behavior.
  - legacy `[ ]` compatibility.
- `VimEngineTests`
  - `gd` appends current line to daily note.
  - `3gd` appends three lines.
  - `gl` remains Linear.
- `ShortcutStoreTests`
  - new actions have defaults and backfill into older persisted shortcut maps.
- `SpotlightWindowControllerTests` or focused controller test
  - append closure is wired through `SpotlightWindow` -> `SpotlightRootView` -> `MultilineEditor`.

Integration/manual smoke:

1. Build and run full tests: `swift test`.
2. Build release and install only from a clean tree: `./scripts/install-release.sh`.
3. Launch SpotNote.
4. Type `[   ] testing`; verify unchecked marker is visibly same bracket width as `[ x ]`.
5. Type a note line, run `gd` or the chosen chord.
6. Verify today's daily note file receives the line at `/Users/davidbeyer/Documents/knowledge/Daily/2026/06-15-2026.md`.
7. Verify the line disappears from SpotNote only after the file append succeeds.
8. Verify statusline remains absent.

## Implementation order

1. Checkbox canonical marker + tests.
2. `DailyNotePathResolver` + `DailyNoteWriter` + tests.
3. Wire `onAppendDailyNote` through window/root/editor.
4. Add editor action and Vim/shortcut commands.
5. Add command feedback messages.
6. Manual HUD smoke and daily-file readback.
7. Install from clean repo only.

## Non-goals for first pass

- No full two-way live sync with Neovim.
- No file watcher.
- No new database.
- No daily-note cleanup/backfill.
- No statusline resurrection.
- No broad plugin abstraction.

## Decision made before build

David chose **append-and-clear**. The implementation follows the Linear safety model: append succeeds first, then SpotNote clears only if the original editor range is still unchanged. Failures preserve the text.
