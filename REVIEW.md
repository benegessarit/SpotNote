# Review instructions

## Review priorities

1. Correctness, data loss, and irreversible side effects.
2. Privacy/security risks around vault writes, Hermes/Linear handoff, Sparkle/notarization, local config, and secrets.
3. User-visible regressions in the HUD, editor, Vim motions, keyboard focus, and app install/launch behavior.
4. Missing tests or smoke evidence for changed behavior.
5. CI/reviewer drift that makes future readiness claims untrustworthy.

## Reviewer roles

- Cursor Bugbot is the only automatic semantic PR reviewer for product-source PRs.
- Reviewdog and Danger are deterministic/advisory PR automation, not semantic reviewers.
- RoboRev is the local commit-level early-warning sensor where enabled.
- Greptile, CodeRabbit, and other AI reviewers are not PR-readiness gates unless David explicitly re-enables them.

## Readiness rule

A PR is not ready until the latest PR head SHA has passing required local/CI checks and terminal reviewer/advisory state, or a blocker/watcher is recorded.

SpotNote's primary local proof is `make ci`. When a full local CI run is too expensive for a tiny workflow-only edit, use the narrowest relevant checks plus a PR check readback, and say the gap plainly.

Feature, script, workflow, integration, install, config, UI, keyboard, and browser-behavior changes need smoke evidence with setup, result, and cleanup whenever a real smoke is possible. If no real smoke is safe or possible, state the reason and the substitute proof.

## Repo-specific risks

- Do not install or launch the live app from disposable or non-canonical worktrees.
- Do not print or commit local secrets from notarization, Sparkle, Hermes ingress, vault paths, or Linear handoff setup.
- Do not treat `make ci` as replaceable by bare `swiftlint`, `periphery`, or `swift test`; SpotNote's scripts pass tuned configs and avoid known false failures.
- UI/HUD/editor changes need a real smoke or a clear no-smoke substitute. Use `scripts/headless-smoke.sh` for agent-safe launch checks when a visible HUD smoke would interrupt David.

## Ignore

- Style-only nits unless they hide a bug.
- Broad rewrites not needed for the PR.
- Speculative architecture suggestions without a concrete failure mode.
