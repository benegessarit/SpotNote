import Foundation

enum VimMode: Equatable, Sendable {
  case normal
  case insert
  case visual
  case visualLine
}

enum Motion: Equatable, Sendable {
  case left(Int)
  case right(Int)
  case up(Int)
  case down(Int)
  case wordForward(Int)
  case wordBackward(Int)
  case wordEnd(Int)
  case lineStart
  case lineEnd
  case firstNonBlank
  case documentStart
  case documentEnd
}

enum VimAction: Equatable, Sendable {
  case none
  case switchToInsert
  case switchToNormal
  case moveCursor(Motion)
  case delete(Motion)
  case deleteLine(count: Int)
  case deleteLineInsert(count: Int)
  case changeBulletBody
  case deleteToEndOfLine
  case deleteChar(count: Int)
  case openLineBelow
  case openLineAbove
  case undo(count: Int)
  case pasteAfter(count: Int)
  case insertAtEndOfLine
  case insertAtFirstNonBlank
  case composite([VimAction])
  case enterCommand
  case enterSearch
  case findNext
  case findPrevious
  case enterFlash(VimFlashDirection, count: Int, scope: VimFlashScope)
  case enterLineFlash(count: Int)
  case sendCurrentTaskToLinear(status: LinearTaskTargetStatus, count: Int)
  case appendCurrentLineToDailyNote(count: Int)
  case appendCurrentLineToTrayNote(count: Int)
  case jumpToTraySection
  case jumpToHabitsSection
  case jumpToToDoSection
  case gotoLine(Int)
  case enterVisual
  case extendVisual(Motion)
  case yankVisualSelection
  case deleteVisualSelection
  case changeVisualSelection
  case enterVisualLine
  case extendVisualLine(Motion)
  case yankVisualLine
  case deleteVisualLineSelection
  case changeVisualLineSelection
}

final class VimEngine {
  private(set) var mode: VimMode = .normal
  private var pendingBuffer: String = ""
  private var countAccumulator: Int = 0

  func handle(key: String, hasModifiers: Bool) -> VimAction {
    if hasModifiers { return .none }

    switch mode {
    case .insert:
      return handleInsert(key: key)
    case .normal:
      return handleNormal(key: key)
    case .visual:
      return handleVisual(key: key)
    case .visualLine:
      return handleVisualLine(key: key)
    }
  }

  func reset() {
    mode = .normal
    pendingBuffer = ""
    countAccumulator = 0
  }

  private func handleInsert(key: String) -> VimAction {
    guard key == "\u{1B}" || key == "escape" else { return .none }
    mode = .normal
    pendingBuffer = ""
    countAccumulator = 0
    return .switchToNormal
  }

  private func handleNormal(key: String) -> VimAction {
    if key.count == 1, let ch = key.first, ch.isNumber {
      let digit = ch.wholeNumberValue ?? 0
      if digit > 0 || countAccumulator > 0 {
        countAccumulator = countAccumulator * 10 + digit
        return .none
      }
    }

    if !pendingBuffer.isEmpty {
      return handlePending(key: key)
    }

    return handleSingle(key: key)
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func handlePending(key: String) -> VimAction {
    let count = resolvedCount
    defer { clearAccumulator() }

    switch pendingBuffer {
    case "d":
      pendingBuffer = ""
      if key == "d" { return .deleteLine(count: count) }
      if let motion = motionForKey(key, count: count) { return .delete(motion) }
      return .none
    case "c":
      if key == "i" {
        pendingBuffer = "ci"
        return .none
      }
      pendingBuffer = ""
      if key == "c" {
        mode = .insert
        return .deleteLineInsert(count: count)
      }
      if key == "B" {
        mode = .insert
        return .changeBulletBody
      }
      if let motion = motionForKey(key, count: count) { return .delete(motion) }
      return .none
    case "ci":
      pendingBuffer = ""
      if key == "b" {
        mode = .insert
        return .changeBulletBody
      }
      return .none
    case "g":
      return handlePendingG(key: key, count: count)
    case "t":
      return handlePendingT(key: key)
    default:
      pendingBuffer = ""
      return .none
    }
  }

  private func handlePendingG(key: String, count: Int) -> VimAction {
    pendingBuffer = ""
    if key == "g" { return .moveCursor(.documentStart) }
    if key == "d" { return .sendCurrentTaskToLinear(status: .done, count: count) }
    if key == "p" { return .sendCurrentTaskToLinear(status: .planned, count: count) }
    if key == "t" { return .sendCurrentTaskToLinear(status: .triage, count: count) }
    if key == "s" { return .sendCurrentTaskToLinear(status: .started, count: count) }
    if key == "l" { return .sendCurrentTaskToLinear(status: .later, count: count) }
    if key == "y" { return .appendCurrentLineToTrayNote(count: count) }
    // Consistent section jumps (capital g-prefix): each jumps to its `## …`
    // section and drops into insert on a fresh bullet.
    if key == "H" { return jumpToSectionInsertAction(.jumpToHabitsSection) }
    if key == "D" { return jumpToSectionInsertAction(.jumpToToDoSection) }
    if key == "T" { return jumpToSectionInsertAction(.jumpToTraySection) }
    return .none
  }

  private func handlePendingT(key: String) -> VimAction {
    pendingBuffer = ""
    if key == "t" { return jumpToSectionInsertAction(.jumpToTraySection) }
    return .none
  }

  private func jumpToSectionInsertAction(_ action: VimAction) -> VimAction {
    mode = .insert
    return action
  }

  private func handleSingle(key: String) -> VimAction {
    if key == "d" || key == "g" || key == "c" || key == "t" {
      pendingBuffer = key
      return .none
    }

    // `<count>G` jumps to a specific line; bare `G` falls through to the
    // documentEnd motion below.
    if key == "G", countAccumulator > 0 {
      let target = countAccumulator
      clearAccumulator()
      return .gotoLine(target)
    }

    let count = resolvedCount
    defer { clearAccumulator() }

    if let motion = motionForKey(key, count: count) {
      return .moveCursor(motion)
    }

    if let action = enterInsertAction(for: key) { return action }
    if let action = flashAction(for: key, count: count) { return action }
    if let action = visualEntryAction(for: key) { return action }
    if let action = editingAction(for: key, count: count) { return action }
    return promptOrSearchAction(for: key)
  }

  private func editingAction(for key: String, count: Int) -> VimAction? {
    switch key {
    case "x": return .deleteChar(count: count)
    case "D": return .deleteToEndOfLine
    case "p": return .pasteAfter(count: count)
    case "u": return .undo(count: count)
    default: return nil
    }
  }

  private func enterInsertAction(for key: String) -> VimAction? {
    switch key {
    case "i":
      mode = .insert
      return .switchToInsert
    case "a":
      mode = .insert
      return .composite([.moveCursor(.right(1)), .switchToInsert])
    case "I":
      mode = .insert
      return .composite([.moveCursor(.firstNonBlank), .switchToInsert])
    case "A":
      mode = .insert
      return .insertAtEndOfLine
    case "o":
      mode = .insert
      return .openLineBelow
    case "O":
      mode = .insert
      return .openLineAbove
    default:
      return nil
    }
  }

  private func promptOrSearchAction(for key: String) -> VimAction {
    switch key {
    case ":": return .enterCommand
    case "/": return .enterSearch
    case "n": return .findNext
    case "N": return .findPrevious
    default: return .none
    }
  }

  private func flashAction(for key: String, count: Int) -> VimAction? {
    switch key {
    case "s": return .enterFlash(.forward, count: count, scope: .document)
    case "S": return .enterFlash(.backward, count: count, scope: .document)
    case "f": return .enterFlash(.forward, count: count, scope: .currentLine)
    case "F": return .enterFlash(.backward, count: count, scope: .currentLine)
    case "K": return .enterLineFlash(count: count)
    default: return nil
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func motionForKey(_ key: String, count: Int) -> Motion? {
    // #lizard forgives
    switch key {
    case "h": return .left(count)
    case "l": return .right(count)
    case "j": return .down(count)
    case "k": return .up(count)
    case "w": return .wordForward(count)
    case "b": return .wordBackward(count)
    case "e": return .wordEnd(count)
    case "0": return .lineStart
    case "$": return .lineEnd
    case "^": return .firstNonBlank
    case "G": return .documentEnd
    default: return nil
    }
  }

  private var resolvedCount: Int { max(1, countAccumulator) }

  private func clearAccumulator() { countAccumulator = 0 }
}

extension VimEngine {
  func visualEntryAction(for key: String) -> VimAction? {
    switch key {
    case "v":
      mode = .visual
      return .enterVisual
    case "V":
      mode = .visualLine
      return .enterVisualLine
    default:
      return nil
    }
  }

  // MARK: - Visual line mode

  private func handleVisualLine(key: String) -> VimAction {
    if !pendingBuffer.isEmpty {
      return handleVisualLinePending(key: key)
    }
    if key.count == 1, let ch = key.first, ch.isNumber {
      let digit = ch.wholeNumberValue ?? 0
      if digit > 0 || countAccumulator > 0 {
        countAccumulator = countAccumulator * 10 + digit
        return .none
      }
    }
    if key == "g" {
      pendingBuffer = "g"
      return .none
    }

    // `<count>G` jumps to a specific line and snaps the visual range
    // to it; bare `G` falls through to the documentEnd motion.
    if key == "G", countAccumulator > 0 {
      let target = countAccumulator
      clearAccumulator()
      return .extendVisualLine(.down(max(0, target - 1)))
    }

    let count = resolvedCount
    defer { clearAccumulator() }

    if let motion = motionForKey(key, count: count) {
      return .extendVisualLine(motion)
    }
    return visualLineCommand(for: key)
  }

  private func handleVisualLinePending(key: String) -> VimAction {
    let buffered = pendingBuffer
    let count = resolvedCount
    pendingBuffer = ""
    if buffered == "g", key == "g" {
      clearAccumulator()
      return .extendVisualLine(.documentStart)
    }
    if buffered == "g", key == "y" {
      clearAccumulator()
      mode = .normal
      return .appendCurrentLineToTrayNote(count: count)
    }
    return .none
  }

  private func visualLineCommand(for key: String) -> VimAction {
    switch key {
    case "V", "\u{1B}", "escape":
      mode = .normal
      return .switchToNormal
    case "y":
      mode = .normal
      return .yankVisualLine
    case "d", "x":
      mode = .normal
      return .deleteVisualLineSelection
    case "c", "s":
      mode = .insert
      return .changeVisualLineSelection
    default:
      return .none
    }
  }

  func handleVisual(key: String) -> VimAction {
    if !pendingBuffer.isEmpty {
      return handleVisualPending(key: key)
    }
    if key.count == 1, let ch = key.first, ch.isNumber {
      let digit = ch.wholeNumberValue ?? 0
      if digit > 0 || countAccumulator > 0 {
        countAccumulator = countAccumulator * 10 + digit
        return .none
      }
    }
    if key == "g" {
      pendingBuffer = "g"
      return .none
    }
    if key == "G", countAccumulator > 0 {
      let target = countAccumulator
      clearAccumulator()
      return .extendVisual(.down(max(0, target - 1)))
    }

    let count = resolvedCount
    defer { clearAccumulator() }

    if let motion = motionForKey(key, count: count) {
      return .extendVisual(motion)
    }
    return visualCommand(for: key)
  }

  private func handleVisualPending(key: String) -> VimAction {
    let buffered = pendingBuffer
    let count = resolvedCount
    pendingBuffer = ""
    if buffered == "g", key == "g" {
      clearAccumulator()
      return .extendVisual(.documentStart)
    }
    if buffered == "g", key == "y" {
      clearAccumulator()
      mode = .normal
      return .appendCurrentLineToTrayNote(count: count)
    }
    return .none
  }

  private func visualCommand(for key: String) -> VimAction {
    switch key {
    case "v", "\u{1B}", "escape":
      mode = .normal
      return .switchToNormal
    case "V":
      mode = .visualLine
      return .enterVisualLine
    case "y":
      mode = .normal
      return .yankVisualSelection
    case "d", "x":
      mode = .normal
      return .deleteVisualSelection
    case "c", "s":
      mode = .insert
      return .changeVisualSelection
    default:
      return .none
    }
  }
}
