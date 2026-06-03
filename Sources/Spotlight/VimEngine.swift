import Foundation

enum VimMode: Equatable, Sendable {
  case normal
  case insert
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

enum TextObject: Equatable, Sendable {
  case innerWord
  case aroundWord
  case innerSentence
  case aroundSentence
  case innerParagraph
  case aroundParagraph
}

enum MarkdownWrapStyle: Equatable, Sendable {
  case bold
  case italic
}

enum VimAction: Equatable, Sendable {
  case none
  case switchToInsert
  case switchToNormal
  case moveCursor(Motion)
  case delete(Motion)
  case deleteLine(count: Int)
  case deleteLineInsert(count: Int)
  case deleteToEndOfLine
  case deleteChar(count: Int)
  case openLineBelow
  case openLineAbove
  case undo(count: Int)
  case insertAtEndOfLine
  case insertAtFirstNonBlank
  case composite([VimAction])
  case enterCommand
  case enterSearch
  case findNext
  case findPrevious
  case enterFlash(VimFlashDirection, count: Int, scope: VimFlashScope)
  case enterLineFlash(count: Int)
  case gotoLine(Int)
  case enterVisualLine
  case extendVisualLine(Motion)
  case yankVisualLine
  case deleteVisualLineSelection
  case changeVisualLineSelection
  case changeTextObject(TextObject)
  case deleteTextObject(TextObject)
  case wrapCurrentWord(MarkdownWrapStyle)
  case wrapVisualLine(MarkdownWrapStyle)
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

  private func handlePending(key: String) -> VimAction {
    let count = resolvedCount
    let buffered = pendingBuffer
    pendingBuffer = ""
    defer { clearAccumulator() }

    switch buffered {
    case "d": return pendingDeleteAction(key: key, count: count)
    case "c": return pendingChangeAction(key: key, count: count)
    case "di": return pendingTextObjectAction(key: key, operation: .delete, scope: .inner)
    case "da": return pendingTextObjectAction(key: key, operation: .delete, scope: .around)
    case "ci": return pendingTextObjectAction(key: key, operation: .change, scope: .inner)
    case "ca": return pendingTextObjectAction(key: key, operation: .change, scope: .around)
    case "g": return key == "g" ? .moveCursor(.documentStart) : .none
    case ";": return pendingWrapAction(key: key)
    default: return .none
    }
  }

  private func pendingDeleteAction(key: String, count: Int) -> VimAction {
    if key == "d" { return .deleteLine(count: count) }
    if key == "i" || key == "a" {
      pendingBuffer = "d\(key)"
      return .none
    }
    guard let motion = motionForKey(key, count: count) else { return .none }
    return .delete(motion)
  }

  private func pendingChangeAction(key: String, count: Int) -> VimAction {
    if key == "c" {
      mode = .insert
      return .deleteLineInsert(count: count)
    }
    if key == "i" || key == "a" {
      pendingBuffer = "c\(key)"
      return .none
    }
    guard let motion = motionForKey(key, count: count) else { return .none }
    return .delete(motion)
  }

  private func pendingWrapAction(key: String) -> VimAction {
    guard let style = wrapStyle(for: key) else { return .none }
    return .wrapCurrentWord(style)
  }

  private func handleSingle(key: String) -> VimAction {
    if key == "d" || key == "g" || key == "c" || key == ";" {
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
    switch key {
    case "x": return .deleteChar(count: count)
    case "D": return .deleteToEndOfLine
    case "u": return .undo(count: count)
    case "V":
      mode = .visualLine
      return .enterVisualLine
    default: return promptOrSearchAction(for: key)
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
    pendingBuffer = ""
    if buffered == "g", key == "g" {
      clearAccumulator()
      return .extendVisualLine(.documentStart)
    }
    if buffered == ";", let style = wrapStyle(for: key) {
      clearAccumulator()
      mode = .normal
      return .wrapVisualLine(style)
    }
    return .none
  }

  private func visualLineCommand(for key: String) -> VimAction {
    switch key {
    case "V", "\u{1B}", "escape":
      mode = .normal
      return .switchToNormal
    case ";":
      pendingBuffer = ";"
      return .none
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

  private func wrapStyle(for key: String) -> MarkdownWrapStyle? {
    switch key {
    case "b": return .bold
    case "i": return .italic
    default: return nil
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

  private func clearAccumulator() {
    countAccumulator = 0
  }
}

private enum TextObjectOperation { case change, delete }
private enum TextObjectScope { case inner, around }

extension VimEngine {
  private func pendingTextObjectAction(
    key: String,
    operation: TextObjectOperation,
    scope: TextObjectScope
  ) -> VimAction {
    guard let object = textObject(for: key, scope: scope) else { return .none }
    switch operation {
    case .change:
      mode = .insert
      return .changeTextObject(object)
    case .delete:
      return .deleteTextObject(object)
    }
  }

  private func textObject(for key: String, scope: TextObjectScope) -> TextObject? {
    switch (scope, key) {
    case (.inner, "w"): return .innerWord
    case (.around, "w"): return .aroundWord
    case (.inner, "s"): return .innerSentence
    case (.around, "s"): return .aroundSentence
    case (.inner, "p"): return .innerParagraph
    case (.around, "p"): return .aroundParagraph
    default: return nil
    }
  }
}
