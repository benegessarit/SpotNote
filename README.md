# SpotNote

A Spotlight-style macOS note capture app. Toggle with **⌘⇧Space**.

Live site: https://spotnote.org

## David's local source of truth

On David's Mac, build and install SpotNote only from:

```bash
/Users/davidbeyer/Projects/SpotNote
```

Do not install from `.hermes/kanban`, `.paperclip-*`, `/tmp`, or other disposable recovery worktrees. This local build carries custom themes, Hermes/Linear handoff, the Hermes toast, no Vim statusline, and a right-shifted HUD position. `AGENTS.md` is the runbook for future agent work.

## Requirements

macOS 14+, Xcode 16+ (Swift 6 toolchain).

## Quick start

```bash
./scripts/setup.sh   # one-time: brew, swift-format, swiftlint, periphery, lizard
./scripts/run.sh     # builds and runs. You can then toggle with the shortcut.
```

Equivalent Make targets exist for every script: `make build`, `make run`, `make test`, `make ci`.

Before replacing the live app, verify the source and use the guarded installer:

```bash
make verify-source
make install
```

`make install` refuses dirty installs by default, backs up `/Applications/SpotNote.app`, verifies the custom binary fingerprints, checks codesigning, and launches the installed app.

## Common tasks

| Task | Script | Make |
| --- | --- | --- |
| Format | `scripts/fmt.sh` | `make fmt` |
| Lint | `scripts/lint.sh` | `make lint` |
| Tests | `scripts/test.sh` | `make test` |
| Build .app | `scripts/build.sh [debug\|release]` | `make build` / `make release` |
| Verify local source | `scripts/verify-source-of-truth.sh` | `make verify-source` |
| Install live app | `scripts/install-release.sh` | `make install` |
| Build + launch | `scripts/run.sh` | `make run` |
| Full pipeline | `scripts/ci.sh` | `make ci` |

`ci.sh` runs: `tools-check -> fmt-check -> lint -> build -> test -> periphery -> complexity`.

## Contributing

Read [`RULES.md`](./RULES.md) before opening a PR. It covers Swift 6 conventions, concurrency, compositing/visual-effects, the linter thresholds CI enforces, and the commit-message format.
