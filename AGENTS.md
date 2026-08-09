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
- The first/default note is the vault-backed Markdown inbox at `~/Documents/knowledge/Captures/spotnote-inbox.md`; JSON chat persistence is secondary app-local library state, not the launch buffer. Recognized section headings are **Title Case** -- `## Todo`, `## Tray` -- and the inbox loader normalizes any recognized heading (any case, any `#` level) to that canonical spelling. The loader does NOT inject or reorder sections; header-less notes stay header-less, and a fresh/missing inbox opens blank instead of inserting a default section.
- The old Vim statusline is removed entirely: no `vimBarHeight` constant and no `VimStatusLine.swift` source file should exist.
- Native Flash-style Vim jumps are restored without terminal embedding or statusline chrome: `VimFlash.swift`, `MultilineEditorFlash.swift`, and `MultilineEditorFlashRendering.swift` own the `S` whole-document backward jump, `f`/`F` same-line jumps, and `K` row/gutter labels. Normal/visual `s` is the hop-style word-hint jump (`VimWordHint.swift` + `MultilineEditorWordHint.swift`): every visible word start gets an instant label (hop.nvim TrieBacktrackFilling charset/order, nearest-first by Manhattan distance with x_bias 10), typed keys narrow labels (never a search query), the document dims while hints show, and label colors are the nvim rose-pine pair (`#eb6f92` primary / `#9ccfd8` alternate for touching runs).
- The editor font is the system sans (SF Pro) at the Raycast Notes body scale via `SpotNoteFont.editor()` -- the former MonoLisa/IBM Plex Mono monospace contract was deliberately retired with the Raycast shell (2026-08-08, David-approved "exact same look" directive).
- Task checkboxes/sign markers are retired from the live editor. Old Markdown `[ ]` / `[x]` storage markers may still parse for compatibility, but SpotNote should not render, reserve, or toggle checkbox gutter chrome. Task completion/status now flows through Linear motions.
- Markdown outline behavior belongs in `MarkdownOutline.swift` and `PlaceholderTextView`: Enter and Vim normal-mode `o`/`O` continue `- ` bullets with the current indentation, Tab indents a bullet by one two-space level, Shift-Tab outdents by one level, and pressing Enter on an empty bullet exits the list. Motions are split by prefix: the `,` prefix jumps to a section and inserts a fresh `- ` bullet at its end (creating it if absent, ignoring internal blank spacers): `,d` → `## Todo`, `,t` → `## Tray`. The `g` prefix is reserved for Linear handoff: `gd/gp/gs/gt/gl` send the bullet to David's Personal workspace at Done/Planned/Started/Triage/Later, and `gc` sends it to his Code workspace at Triage with the assignable `Develop` label. The `\` leader handles other sends and is reusable: `\t` appends the current line to spotnote-tray.md; `\c` appends the current bullet block(s) to the hermes-build State.md (`~/Documents/knowledge/Work/hermes-build/Notes/State.md`) as one flattened `- ` line per block, then clears the source (`N\c` files N separate `- ` lines, not one fused line); and `\f` (or `:fmt`) tidies blank-line spacing around section headers (one blank line above and below each header, none above the top header), preserving bullets and multiline bullets. (Legacy `gH/gD/gT/tt/gy`, `,h`, `,b`, and `\h` are retired.)
- With line numbers hidden, the editor reserves no task/checkbox gutter (`LineNumberRuler.thickness(...) == 0`) and uses `EditorMetrics.textLeadingGap == 37` for the Raycast-style body inset (pixel-measured from the live Raycast Notes window).
- The editor text is the Raycast Notes body scale, pixel-measured from David's live Raycast Beta Notes window (2026-08-08): `EditorMetrics.fontSize == 20` with `EditorMetrics.lineHeight == 41` (their line box + paragraph spacing, applied uniformly), panel width 670, on a full-bleed 26pt-radius surface (circle-fit on the live Raycast window border arc). Themes with `Theme.backgroundTop` (raycast-dark: `#2A2C3B` → `#252634`) render Raycast's full-height vertical surface gradient; flat themes keep the near-opaque glass tint. ALL panels are borderless (`SpotlightWindowController.panelStyleMask`); the traffic lights are drawn by `RaycastTrafficLights` in SwiftUI (14pt dots, 23pt centers, Display-P3 close red `#EC6765` + two disabled greys) because Raycast Notes draws its own. The top bar (60pt: lights, centered 16pt first-line title, trailing 44pt capsule -- solid `#25262E`, white-0.08 border -- with the exact @raycast/icons command/plus rasters plus a custom fanned-cards note-switcher glyph) and bottom bar (56pt: 16pt character counter only; theme switching lives in the actions modal, the old circled-T button is retired) hide their controls when the panel is not key (`PanelKeyState`), matching Raycast's resigned state -- only the (dimmed) title and counter remain. The bars are ALWAYS-present chrome: `EditorMetrics.topBarHeight`/`bottomBarHeight` are mirrored in BOTH `SpotlightRootView.extraChromeHeight` and the controller's `chromeAboveEditor`/`chromeBelowEditor`. Note browsing, actions, and the theme picker are Raycast-style floating modals (`RaycastNotesModal` over `FuzzyController` + `RaycastActionsModal` from the ⌘ pill button in `RaycastModals.swift`; `RaycastThemesModal.swift`) rendered in a `SpotlightRootView` `.overlay` over a dimmed surface -- they NEVER contribute panel height (guarded by `SpotlightRootToastTests.notesModalDoesNotTriggerPanelHeightCallbacks`) and never spawn child windows. The old embedded fuzzy palette + separate preview panel are retired. The notes sidebar (`SpotNoteSidebar.swift`, ⌘\ or the actions modal) slides in on the LEFT: the window grows leftward by `EditorMetrics.sidebarWidth == 250` with the right edge pinned so the editor column never rewraps, and it also never contributes measured height (`sidebarToggleDoesNotTriggerPanelHeightCallbacks`). The panel frame is fully programmatic: the `NSHostingView` has `sizingOptions = []` -- restoring default sizing options re-introduces a sidebar-close clamp that strands a 920pt-wide window.
- Empty/short notes open compact and grow per line, like Raycast Notes: `EditorMetrics.roomyVisibleLinesFloor == 1`, so the empty window is 670x177pt (60 top bar + 20 inset + one 41pt line + 56 bottom bar -- pixel-measured against the live Raycast empty window). The old 6-line roomy floor was based on a ref screenshot that had content.
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

Headless launch uses `SPOTNOTE_HEADLESS_TEST=1`, initializes the app bundle, verifies no visible SpotNote windows were created, then exits/cleans up. Normal user launch remains HUD-first. If `SPOTNOTE_FINAL_LAUNCH_MODE=headless` is used for final install verification, it exits by design; before handing SpotNote back to David, relaunch `/Applications/SpotNote.app` normally and read back `pgrep -fl '/Applications/SpotNote.app|SpotNote'` so the global-hotkey app is resident.

## Manual smoke after install

- Launch/toggle SpotNote with `⌘⇧Space`.
- Confirm the panel opens in the bottom-right corner (inset from the right/bottom edges) and grows upward as you type.
- Confirm editor text renders in the system sans at the Raycast body scale.
- Confirm `- ` bullets continue with Enter/normal-mode `o`, Tab indents, and Shift-Tab outdents.
- Confirm Title-Case headings; in Vim normal mode, `,d`/`,t` jump to `## Todo`/`## Tray` and drop onto a fresh `- ` bullet at the end of each (creating the section if absent). `\t` appends the current line to spotnote-tray.md; `\c` appends the current bullet to the hermes-build State.md and clears it; `\f` tidies blank-line spacing around headers.
- Confirm there is no task checkbox/sign gutter and `gg` does not shift text into old checkbox space.
- Confirm no bottom Vim statusline appears.
- In Vim normal mode, confirm `s` starts inline Flash labels, `f` limits labels to the current line, and `K` replaces gutter line numbers with row labels.
- Type a task, optionally with `#Label` and `due:today` / `due:tomorrow` / `due:MM-dd-yyyy`, then use Vim normal-mode `gd`/`gp`/`gt`/`gs`/`gl` for Done/Planned/Triage/Started/Later Linear handoff to the Personal workspace, or `gc` for a Triage+Build issue in the Code workspace. The bullet should delete only after successful handoff and show a Hermes toast.

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
