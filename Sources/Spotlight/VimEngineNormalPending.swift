import Foundation

/// Normal-mode pending-prefix dispatch for `VimEngine`, split out so `VimEngine.swift`
/// stays within its length budget. Prefixes:
/// - `d`/`c`/`y` (+ `i`/`a` object stages): the operator grammar -- one handler
///   composes any operator with any motion or text object.
/// - `g`: Linear handoff (`gd/gp/gs/gt/gl` → personal; `gc` → Code workspace); `gg`
///   keeps the document-start motion.
/// - `,`: section jumps (`,d/,t`) that drop into insert on a fresh bullet.
/// - `\`: reusable leader (`\t` tray-append, `\c` state-append, `\f` tidy header spacing).
extension VimEngine {
  func handlePending(key: String) -> VimAction {
    let count = pendingResolvedCount
    defer { clearAccumulator() }

    switch pendingBuffer {
    case "d", "c", "y":
      return handleOperatorPending(key: key, count: count)
    case "di", "da", "ci", "ca", "yi", "ya":
      return handleObjectPending(key: key)
    case "g": return handlePendingG(key: key, count: count)
    case ",": return handlePendingComma(key: key)
    case "\\": return handlePendingBackslash(key: key, count: count)
    default:
      resolvePending()
      return .none
    }
  }

  private var pendingOperator: VimOperator? {
    switch pendingBuffer.first {
    case "d": return .delete
    case "c": return .change
    case "y": return .yank
    default: return nil
    }
  }

  /// Ends the pending sequence: the prefix and its captured count die
  /// together (a half-typed operator must not leak its count into the
  /// next keystroke).
  private func resolvePending() {
    pendingBuffer = ""
    pendingCount = 0
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func handleOperatorPending(key: String, count: Int) -> VimAction {
    guard let op = pendingOperator else {
      resolvePending()
      return .none
    }
    // `i`/`a` advance to the text-object stage without resolving.
    if key == "i" || key == "a" {
      pendingBuffer += key
      return .none
    }
    let doubled =
      (op == .delete && key == "d") || (op == .change && key == "c")
      || (op == .yank && key == "y")
    if doubled {
      resolvePending()
      switch op {
      case .delete: return .deleteLine(count: count)
      case .change:
        enterInsertMode()
        return .deleteLineInsert(count: count)
      case .yank: return .yankLine(count: count)
      }
    }
    if op == .change, key == "B" {
      resolvePending()
      enterInsertMode()
      return .changeBulletBody
    }
    if let motion = motionForKey(key, count: count) {
      resolvePending()
      if op == .change { enterInsertMode() }
      return .applyOperator(op, .motion(motion))
    }
    resolvePending()
    return .none
  }

  /// Text-object stage (`diw`, `caw`, `yiw`, ... plus the established
  /// `cib` = change bullet body).
  private func handleObjectPending(key: String) -> VimAction {
    guard let op = pendingOperator else {
      resolvePending()
      return .none
    }
    let around = pendingBuffer.hasSuffix("a")
    resolvePending()
    if op == .change, key == "b", !around {
      enterInsertMode()
      return .changeBulletBody
    }
    if key == "w" {
      if op == .change { enterInsertMode() }
      return .applyOperator(op, around ? .aroundWord : .innerWord)
    }
    return .none
  }

  // `g` is the Linear handoff prefix. `g` + status sends the current bullet to
  // David's personal Linear at that state (gd/gp/gt/gs/gl). `gc` sends it to his
  // Code workspace at Triage (the editor adds the Develop label). `gg` keeps the
  // document-start motion.
  private func handlePendingG(key: String, count: Int) -> VimAction {
    resolvePending()
    if key == "g" { return .moveCursor(.documentStart) }
    if key == "d" {
      return .sendCurrentTaskToLinear(status: .done, workspace: .personal, count: count)
    }
    if key == "p" {
      return .sendCurrentTaskToLinear(status: .planned, workspace: .personal, count: count)
    }
    if key == "t" {
      return .sendCurrentTaskToLinear(status: .triage, workspace: .personal, count: count)
    }
    if key == "s" {
      return .sendCurrentTaskToLinear(status: .started, workspace: .personal, count: count)
    }
    if key == "l" {
      return .sendCurrentTaskToLinear(status: .later, workspace: .personal, count: count)
    }
    if key == "c" {
      return .sendCurrentTaskToLinear(status: .triage, workspace: .code, count: count)
    }
    return .none
  }

  // `,` is the section-jump prefix: jump to a `## …` section and drop into
  // insert on a fresh bullet (creating the section if absent).
  private func handlePendingComma(key: String) -> VimAction {
    resolvePending()
    if key == "d" { return jumpToSectionInsertAction(.jumpToToDoSection) }
    if key == "t" { return jumpToSectionInsertAction(.jumpToTraySection) }
    return .none
  }

  // `\` is a reusable leader. `\t` appends the current line to spotnote-tray.md; `\c`
  // appends the current bullet(s) to the hermes-build State.md (one clean `- ` line
  // per block, then clears the source); `\f` tidies blank-line spacing around section
  // headers (one line above and below each header, none above the top header).
  private func handlePendingBackslash(key: String, count: Int) -> VimAction {
    resolvePending()
    if key == "t" { return .appendCurrentLineToTrayNote(count: count) }
    if key == "c" { return .appendCurrentLineToStateNote(count: count) }
    if key == "f" { return .normalizeDocument }
    return .none
  }

  private func jumpToSectionInsertAction(_ action: VimAction) -> VimAction {
    enterInsertMode()
    return action
  }
}
