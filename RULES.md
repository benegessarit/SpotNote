# SpotNote Engineering Rules

**Target:** macOS-native app (SwiftUI + AppKit) written in Swift 6.
**Scope:** This document is the single source of truth for conventions, tooling, and workflows. Read it in full before authoring code or tests.

---

## 0. Philosophy

Lean over clever. The smallest working implementation wins. No speculative abstractions, no protocols added "just in case", no dead parameters.

Trust the type system. Prefer `Sendable`, actors, non-optional types, and exhaustive enums over runtime guards. Compile-time correctness beats runtime checks.

Measure, don't guess. Every performance claim is backed by an Instruments trace. No micro-optimisations without a profile.

Every public symbol is a commitment. Default access is `internal`. `public` only when the symbol crosses a module boundary as a considered API.

Keep pure logic out of the UI. State machines, parsers, and geometry are value types with no AppKit/SwiftUI imports, so they can be unit-tested without a view.

---

## 1. Swift Language Rules

### 1.1 Naming
- `UpperCamelCase` for types, protocols, enum cases.
- `lowerCamelCase` for everything else.
- Acronyms follow surrounding case: `urlSession`, `HTTPServer`, `jsonDecoder`.
- File name = primary type name (`NoteEditorView.swift` contains `NoteEditorView`).
- Protocols describing what something *is* use nouns (`Collection`); capability protocols use `-able` / `-ing` (`Equatable`, `ProgressReporting`).
- Booleans read as assertions: `isEmpty`, `hasPrefix(_:)`.

### 1.2 Access Control
- Default to `internal`. `private` for type-internal detail. `fileprivate` only when same-file extensions need access.
- Mark types and methods `final` unless subclassing is a designed extension point.
- `public` symbols carry a doc comment explaining the contract.

### 1.3 Types
- Prefer `struct`. Reach for `class` only for reference semantics, Objective-C interop, or identity.
- Prefer `enum` with associated values over a pair of optionals or a `type` string.
- Never `force-unwrap` (`!`), `force-cast` (`as!`), or `try!` in production code. The linter blocks them.
- Use `Result<Success, Failure>` only when bridging async callback APIs; in async code, throw.

### 1.4 Immutability
- `let` by default. `var` only when mutation is required.
- Value types are `Sendable` by default. Reference types must explicitly conform or be actors.

### 1.5 Control Flow
- Prefer `guard` for early exits over nested `if`.
- Prefer `for ... in` and higher-order functions (`map`/`filter`/`reduce`) over `while` for collections.
- Exhaustive `switch` over enums. No `default:` on internal/private enums so the compiler warns when cases are added.

### 1.6 Documentation
- Doc comments are encouraged but not linter-enforced. Write `///` only when the *why* is non-obvious.
- Skip them when a well-named identifier already says everything.
- When you do write one, prefer Swift Markdown: `- Parameters:`, `- Returns:`, `- Throws:`, `- Complexity:` (big-O) where the function is algorithmic.
- Long files (>400 lines) are themselves a smell. Split.

### 1.7 Errors
- Model domain errors as `enum MyFeatureError: Error, Equatable { ... }`.
- Attach `LocalizedError` when the error can reach the UI.
- Do not swallow errors (`try? ...; // ignore`) without a `// swiftlint:disable:next` justification.

---

## 2. Concurrency (Swift 6)

1. Build with strict concurrency = Complete (`SWIFT_STRICT_CONCURRENCY=complete`). Compile warnings about data races are errors.
2. Never use `@unchecked Sendable` or `nonisolated(unsafe)` as a shortcut. If the compiler complains, there is a real race; fix the design.
3. UI state lives on `@MainActor`. Views, view models, and anything that mutates observable state must be `@MainActor`-isolated.
4. Protect shared mutable state with `actor`. Actors are preferred over locks, `DispatchQueue` serialisation, or `NSLock`.
5. Use structured concurrency (`async let`, `TaskGroup`, `withTaskGroup`) before reaching for unstructured `Task { }`. Every unstructured task has a documented lifecycle and explicit cancellation.
6. Always check `Task.checkCancellation()` inside long-running loops.
7. `async` functions throw `CancellationError`; handle it up to a UI boundary and ignore silently there.
8. Prefer `AsyncStream` / `AsyncSequence` for event pipelines over Combine.
9. GCD (`DispatchQueue`) is permitted only for bridging C APIs (e.g. the Carbon global-hotkey callback) and AppKit appearance-timed work. Prefer structured concurrency everywhere else.

---

## 3. UI Architecture (SwiftUI)

SpotNote uses SwiftUI-first MVVM with composable feature modules. TCA is not adopted by default.

### 3.1 Layering
- `View` (SwiftUI): layout, bindings, no business logic, no `Task`-firing beyond `.task { await model.load() }`.
- `ViewModel` (`@Observable` class, `@MainActor`): owns view state, calls into `Core` services. Holds no `View` references.
- `Service` / `Repository` (in `Core`/`Persistence`): async, `Sendable`, no UI imports.

### 3.2 State
- Prefer Swift 5.9+ `@Observable` macro over `ObservableObject`/`@Published`. Less boilerplate, finer-grained invalidation.
- Pass state down via `let` properties or `Binding`. Never use `EnvironmentObject` as a grab bag.
- `@Environment` is reserved for app-wide services (theme, feature flags).

---

## 4. Compositing & Visual Effects

SpotNote has no Metal layer. The HUD's translucency is AppKit compositing, not a custom render pipeline.

### 4.1 Materials
- The glass panel is an `NSVisualEffectView` (see `SpotNoteVisualEffectView`). Pick the blur material deliberately; do not stack multiple effect views to fake depth.
- Tint over the material is a single translucent fill (`SpotlightRootView.glassTintOpacity`). Tune transparency there, in one place, not per call site.

### 4.2 Text rendering
- Editor styling uses TextKit: `NSLayoutManager` temporary attributes (`addTemporaryAttribute`) for syntax/heading color so styling never mutates `NSTextStorage` or invalidates the layout cache on every keystroke.
- Compile any `NSRegularExpression` built from a compile-time-constant pattern once (a `static let`), never per keystroke.

### 4.3 If real GPU rendering is ever added
Add it under a new `Sources/Rendering` target and write the Metal discipline (command submission, storage modes, pipeline-state caching, MSL conventions) into this section then — not before. Aspirational rules for code that does not exist are drift.

---

## 5. Tooling & Static Analysis

All tools are vendored via SPM plugins or Homebrew and invoked from `make` targets and CI.

### 5.1 Formatter (`swift-format`)
- Config: `Tools/.swift-format`.
- Line length: 120. Indent: 2 spaces.
- Run in CI: `swift-format lint --strict --recursive Sources Tests` must exit 0.

### 5.2 Linter (`SwiftLint`)
- Config: `Tools/.swiftlint.yml`.
- Complexity thresholds (errors, not warnings):
  - `cyclomatic_complexity`: warning 10, error 15.
  - `function_body_length`: warning 40, error 80.
  - `type_body_length`: warning 250, error 400.
  - `file_length`: warning 400, error 700.
- `swiftlint analyze` (cross-file rules) is available via `make analyze`; the CI lint gate itself runs `swiftlint --strict`.

### 5.3 Dead Code (`Periphery`)
- `make periphery` runs `periphery scan` configured by `Tools/.periphery.yml` (retains `@objc`-accessible and assign-only members). New unused declarations fail the run.
- Annotate intentional exceptions: `// periphery:ignore - exposed for SwiftUI previews`.

### 5.4 Complexity Analysis
- SwiftLint enforces cyclomatic complexity (warning 10, error 15). Target mean CC <= 5 per function; any function > 10 must be justified in code review.
- `make complexity` runs `lizard` in CI with the project's tuned thresholds (CCN 17, length 100, arguments 7). CI fails on violations.
- Write a `- Complexity:` doc line on a public algorithmic function when the big-O is non-obvious (e.g. `- Complexity: O(n log n)`).

### 5.5 Other
- Build is warning-clean: `swift build` produces zero warnings.
- The full test suite must pass (`make test`) before every release.

---

## 6. Testing

### 6.1 Frameworks
- Unit & integration tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- UI tests and performance tests stay on `XCTest` (`XCUIApplication`, `XCTMetric`).
- Do not mix the two within a single suite.

### 6.2 What to Test
- All pure logic in `Core` is unit-tested. Aim for >= 85% line coverage in `Core`, >= 70% overall.
- View models: test state transitions, not view output.

### 6.3 Test Quality
- One behaviour per test, full-sentence names: `@Test("loads notes sorted by most-recently-edited")`.
- Prefer parameterised tests over `for`-loops inside a test.
- No `sleep(_:)`. Wait via clocks or event-driven expectations.
- No real network. Stub at `URLProtocol` or repository layer.
- No real clock. Inject one (`ContinuousClock` / test double).
- Tests are deterministic or they are deleted.

---

## 7. Build, CI, and Release

- Single `Makefile` entry points: `make fmt`, `make lint`, `make test`, `make analyze`, `make periphery`, `make complexity`, `make ci` (runs the full gate).
- `make ci` runs, in order: `tools-check` -> `fmt-check` (`swift-format lint --strict`) -> `lint` (`swiftlint --strict`) -> `build` (`swift build`) -> `test` (`swift test`) -> `periphery` -> `complexity` (`lizard`).
- Zero-warning policy: `swift build` is warning-clean.
- `main` is always releasable. Feature branches rebase onto `main` before merge; no merge commits.

### 7.1 Commit Style
- Format: `<short-tag>: all lowercase and concise msg`.
  - `bug-fix: unexpected app termination on Intel chips`
  - `feat: add a translucent blur behind the Spotlight panel`
- Lowercase EXCEPT legitimate acronyms: API, URL, CPU, GPU, UI, UX, MSL, SPM, CI, CD, macOS, iOS, JSON, HTML, HTTP, I/O, etc.
- Tags: `feat`, `bug-fix`, `fix`, `perf`, `refactor`, `test`, `docs`, `style`, `build`, `chore`, `ci`, `revert`.
- Subject line <= 72 chars. No trailing period. Imperative mood.
- Body is optional; when present, separate from subject with a blank line and wrap at ~100 chars.
- One logical change per commit.
