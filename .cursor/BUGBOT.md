# Cursor Bugbot instructions

Use `REVIEW.md` as the human review charter. Focus on concrete bugs, user-visible regressions, privacy/security risks, data-loss risks, and missing proof for changed behavior.

Report findings only when they include:

- path and line or exact surface;
- failure mode;
- severity;
- suggested fix or proof needed.

Pay special attention to:

- vault-backed inbox writes and deletion/clearing behavior;
- Hermes/Linear handoff and local ingress behavior;
- macOS focus, global hotkeys, HUD visibility, and install/launch paths;
- Swift 6 concurrency and `@MainActor` boundaries;
- tests or smoke evidence missing for UI/editor/Vim-motion changes.

Do not spend review budget on style-only nits, speculative rewrites, or suggestions already enforced by deterministic CI.

Cursor Bugbot is the only automatic semantic reviewer for this repo unless David explicitly changes the repo-quality registry.
