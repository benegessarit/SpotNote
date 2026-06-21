# SpotNote Agent Runbook

SpotNote's stable source of truth on David's Mac is this repo:

```text
/Users/davidbeyer/Projects/SpotNote
```

Do not build or install SpotNote from disposable worktrees such as `.hermes/kanban`, `.paperclip-*`, `/tmp`, or ad hoc recovery directories. Those are allowed for experiments only; any accepted work must be copied or recreated here, git-tracked, tested, and committed before it replaces `/Applications/SpotNote.app`.

## Current custom contract

The local David build intentionally differs from upstream SpotNote:

- Catppuccin and Rosé Pine themes are present in `Sources/Spotlight/Theme.swift`.
- Linear handoff is routed through `Sources/Spotlight/ScratchpadHandoff.swift` to the local Hermes ingress endpoint.
- Hermes feedback uses `Sources/Spotlight/HermesToastView.swift` plus `Sources/Spotlight/Resources/HermesLogo.png`.
- The first/default note is the vault-backed Markdown inbox at `~/Documents/knowledge/Captures/spotnote-inbox.md`; JSON chat persistence is secondary app-local library state, not the launch buffer. Section headings are **Title Case** -- `## Big Things`, `## Habits`, `## Todo`, `## Tray` -- and the inbox loader normalizes any recognized heading (any case, any `#` level) to that canonical spelling. The loader does NOT inject or reorder sections; it only prepends a default `## Habits` when the note starts with no recognized section at all (a fresh/cleared inbox). `## Big Things` is a top, jump-less section.
- The old Vim statusline is removed entirely: no `vimBarHeight` constant and no `VimStatusLine.swift` source file should exist.
- Native Flash-style Vim jumps are restored without terminal embedding or statusline chrome: `VimFlash.swift`, `MultilineEditorFlash.swift`, and `MultilineEditorFlashRendering.swift` own `s`/`S` whole-document jumps, `f`/`F` same-line jumps, and `K` row/gutter labels.
- The editor and numeric gutter font should resolve to IBM Plex Mono via `SpotNoteFont.editorFontName == "IBMPlexMono"`; do not silently fall back to Inter or generic system font for the HUD text surface.
- Task checkboxes/sign markers are retired from the live editor. Old Markdown `[ ]` / `[x]` storage markers may still parse for compatibility, but SpotNote should not render, reserve, or toggle checkbox gutter chrome. Task completion/status now flows through Linear motions.
- Markdown outline behavior belongs in `MarkdownOutline.swift` and `PlaceholderTextView`: Enter and Vim normal-mode `o`/`O` continue `- ` bullets with the current indentation, Tab indents a bullet by one two-space level, Shift-Tab outdents by one level, and pressing Enter on an empty bullet exits the list. In Vim normal mode the section jumps each move in and insert a fresh `- ` bullet at the end of the section (creating it if absent, ignoring internal blank spacers): `gH` → `## Habits`, `gD` → `## Todo`, `gT` → `## Tray` (`tt` is a `gT` alias). `## Big Things` has no jump but the jump logic keeps it at the top (Habits is created below it).
- With line numbers hidden, the editor reserves no task/checkbox gutter (`LineNumberRuler.thickness(...) == 0`) and uses `EditorMetrics.textLeadingGap == 17` for near-card-edge text placement.
- The editor text is the slightly-smaller nvim-like scale: `EditorMetrics.fontSize == 22`, with line numbers matching that same value.
- Short notes open roomy/tall: `EditorMetrics.roomyVisibleLinesFloor == 9`, which makes the four-line inbox panel about 2x the old height.
- The HUD opens in the bottom-right corner of the visible frame, inset by `SpotlightWindowController.defaultEdgeInset` from the right and bottom edges, and is bottom-anchored so it grows upward as content reflows. Guarded by `SpotlightWindowControllerTests.defaultHUDOriginHugsRightEdge` and `defaultHUDOriginHugsBottomEdge`.
- The editor card has no top-right copy icon; keep copy available through keyboard/menu actions instead of visible chrome.

## Safe edit flow

1. Inspect state first:

   ```bash
   git status --short --branch -uall
   ./scripts/verify-source-of-truth.sh
   ```

2. Make the smallest focused change.
3. Run focused tests for touched behavior, then the normal ladder:

   ```bash
   ./scripts/fmt-check.sh
   ./scripts/lint.sh
   ./scripts/test.sh
   ./scripts/build.sh release
   ```

4. Stage exact files only; never use broad `git add -A` in a dirty tree.
5. Commit the source change before live install unless David explicitly asks for an uncommitted visual trial.
6. Install only from this repo:

   ```bash
   ./scripts/install-release.sh
   ```

`install-release.sh` refuses dirty installs by default, backs up the current app under `~/Library/Application Support/SpotNote/AppBackups/`, installs `build/SpotNote.app`, verifies codesigning, and checks the custom binary fingerprints before launching.

For agent/CI launch checks that must not steal David's active Space, use the explicit headless smoke path instead of opening the HUD:

```bash
./scripts/headless-smoke.sh release
SPOTNOTE_FINAL_LAUNCH_MODE=headless ./scripts/install-release.sh
```

Headless launch uses `SPOTNOTE_HEADLESS_TEST=1`, initializes the app bundle, verifies no visible SpotNote windows were created, then exits/cleans up. Normal user launch remains HUD-first.

## Manual smoke after install

- Launch/toggle SpotNote with `⌘⇧Space`.
- Confirm the panel opens in the bottom-right corner (inset from the right/bottom edges) and grows upward as you type.
- Confirm editor text and line numbers render in IBM Plex Mono.
- Confirm `- ` bullets continue with Enter/normal-mode `o`, Tab indents, and Shift-Tab outdents.
- Confirm Title-Case headings; in Vim normal mode, `gH`/`gD`/`gT` jump to `## Habits`/`## Todo`/`## Tray` and drop onto a fresh `- ` bullet at the end of each (creating the section if absent), with `## Big Things` left at the top.
- Confirm there is no task checkbox/sign gutter and `gg` does not shift text into old checkbox space.
- Confirm no bottom Vim statusline appears.
- In Vim normal mode, confirm `s` starts inline Flash labels, `f` limits labels to the current line, and `K` replaces gutter line numbers with row labels.
- Type a task, optionally with `#Label` and `due:today` / `due:tomorrow` / `due:MM-dd-yyyy`, then use Vim normal-mode `gd`/`gp`/`gt`/`gs`/`gl` for Done/Planned/Triage/Started/Later Linear handoff. The bullet should delete only after successful handoff and show a Hermes toast.

## Swift tooling footguns

These bit real sessions; check them before claiming green:

- **Report CI status from the repo's own gate, not a bare tool.** `make ci` / `scripts/ci.sh` (and `scripts/periphery.sh`) pass the repo configs. A bare `periphery scan --strict` ignores `Tools/.periphery.yml` (`retain_objc_accessible`, `retain_assign_only_properties`) and reports false dead-code "failures"; a bare `swiftlint` likewise misses the config. Use the scripts.
- **swift-format vs SwiftLint `opening_brace`:** a multi-line `if`/`guard` condition makes `swift-format` put `{` on its own line, which SwiftLint's `opening_brace` rejects. Hoist the condition into a `let` so the statement is single-line.
- **`swift-format` forbids trailing commas** in collection literals (`[TrailingComma]`); don't leave one on the last element. `./scripts/fmt.sh` auto-fixes.
- **`lizard` mis-parses `await x.get(...)` (the `get` getter keyword) and inline trailing closures**, inflating a function's reported length into a false complexity failure. Fix by extracting the closure to a `let`, or annotate the function `// #lizard forgives`.
- **Optional stored field in a memberwise init:** `let x: T? = nil` is OMITTED from the synthesized memberwise init (callers can't set it); `var x: T? = nil` triggers SwiftLint `redundant_optional_initialization`. To keep it `let` *and* settable, write an explicit init (and `// #lizard forgives` if the param count trips lizard).
- **Changing tested behavior trips `verify-source-of-truth.sh`:** it hard-codes contract greps (test names, constant values, heading spellings, AGENTS.md phrases). A behavior change isn't done until you sweep those greps here too, or `make install` aborts.
- **Install from a worktree:** `install-release.sh`/`verify-source-of-truth.sh` gate on the canonical repo root; pass `SPOTNOTE_ALLOW_NONSTANDARD_ROOT=1`. Never `swift run` during dev loops — it launches a second GUI instance; use `swift build`/`swift test` and the installer.

## Boundaries

- Do not print or commit secrets from local config, notarization, Sparkle, or Hermes ingress setup.
- Do not modify `/Applications/SpotNote.app` without a backup and post-install readback.
- Do not treat the installed binary as source. If app strings and repo source diverge, stop and recover/migrate the source before building over the app.
