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
- The first/default note is the vault-backed Markdown inbox at `~/Documents/knowledge/Captures/spotnote-inbox.md`; JSON chat persistence is secondary app-local library state, not the launch buffer.
- The old Vim statusline is removed entirely: no `vimBarHeight` constant and no `VimStatusLine.swift` source file should exist.
- Native Flash-style Vim jumps are restored without terminal embedding or statusline chrome: `VimFlash.swift`, `MultilineEditorFlash.swift`, and `MultilineEditorFlashRendering.swift` own `s`/`S` whole-document jumps, `f`/`F` same-line jumps, and `K` row/gutter labels.
- The line-number gutter matches the old spacing with `EditorMetrics.leadingInset == 28` and `EditorMetrics.textLeadingGap == 18`; do not only move the whole editor group when fixing number/text spacing.
- The editor text is the slightly-smaller nvim-like scale: `EditorMetrics.fontSize == 22`, with line numbers matching that same value.
- Short notes open roomy/tall: `EditorMetrics.roomyVisibleLinesFloor == 9`, which makes the four-line inbox panel about 2x the old height.
- The HUD opens horizontally centered and vertically centered slightly below the screen midline, guarded by `SpotlightWindowControllerTests.defaultHUDOriginIsHorizontallyCentered` and `defaultHUDOriginIsSlightlyBelowMidline`.

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

## Manual smoke after install

- Launch/toggle SpotNote with `⌘⇧Space`.
- Confirm the panel opens horizontally centered and slightly below the screen midline.
- Confirm no bottom Vim statusline appears.
- In Vim normal mode, confirm `s` starts inline Flash labels, `f` limits labels to the current line, and `K` replaces gutter line numbers with row labels.
- Type a line, then use `⌘⌥L` or Vim normal-mode `gl` to send it to Linear; the line should delete only after successful handoff and show a Hermes toast.

## Boundaries

- Do not print or commit secrets from local config, notarization, Sparkle, or Hermes ingress setup.
- Do not modify `/Applications/SpotNote.app` without a backup and post-install readback.
- Do not treat the installed binary as source. If app strings and repo source diverge, stop and recover/migrate the source before building over the app.
