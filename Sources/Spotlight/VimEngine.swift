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
  /// `<n>G` as a MOTION so visual mode can extend to an absolute line
  /// (the old relative `down(n-1)` snap walked from the caret, not
  /// line n). Normal mode keeps the `.gotoLine` action.
  case toLine(Int)
}

enum VimAction: Equatable, Sendable {
  case none
  case switchToInsert
  case switchToNormal
  case moveCursor(Motion)
  /// Operator × range-producer composition (d/c/y over motions and text
  /// objects) -- the applicator resolves the range and applies the
  /// operator in one place (`MultilineEditorVimOperator.swift`).
  case applyOperator(VimOperator, VimRangeTarget)
  case yankLine(count: Int)
  case deleteLine(count: Int)
  case deleteLineInsert(count: Int)
  case changeBulletBody
  case deleteToEndOfLine
  case deleteChar(count: Int)
  /// `X` -- delete before the caret, clamped to the line start. Like `x`
  /// it deliberately skips the register (small-delete noise).
  case deleteCharBefore(count: Int)
  /// `J` -- join the next line up with a single space, count-1 extra
  /// joins (vim: 3J joins three lines).
  case joinLines(count: Int)
  /// `~` -- toggle case under the caret and advance, count chars.
  case toggleCase(count: Int)
  /// `r<char>` -- replace count chars with the typed char, caret on the
  /// last replacement; aborts when the line runs out (vim).
  case replaceChar(String, count: Int)
  /// `<M-j>`/`<M-k>` -- David's mini.move maps: slide the caret's line
  /// (normal) or the selected line block (visual, selection kept) down/up
  /// count steps, clamping SILENTLY at the buffer edges (his config
  /// retired the `:move` maps precisely because they errored at the top).
  case moveLinesDown(count: Int)
  case moveLinesUp(count: Int)
  case openLineBelow
  case openLineAbove
  case undo(count: Int)
  case pasteAfter(count: Int)
  /// `P` -- paste before the caret (charwise) or above the current line
  /// (linewise).
  case pasteBefore(count: Int)
  case insertAtEndOfLine
  case insertAtFirstNonBlank
  case composite([VimAction])
  case enterCommand
  case enterSearch
  case findNext
  case findPrevious
  case enterFlash(VimFlashDirection, count: Int, scope: VimFlashScope)
  case enterLineFlash(count: Int)
  case enterWordHint
  case sendCurrentTaskToLinear(
    status: LinearTaskTargetStatus,
    workspace: LinearTaskWorkspace,
    count: Int
  )
  case appendCurrentLineToDailyNote(count: Int)
  case appendCurrentLineToTrayNote(count: Int)
  case appendCurrentLineToStateNote(count: Int)
  case normalizeDocument
  case jumpToTraySection
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
  /// Visual `o` -- swap the anchor and the moving end (both wises).
  case swapVisualEnds
  /// Visual `p` -- replace the selection with the register WITHOUT
  /// clobbering it (David's nvim maps visual p to `"_dP`).
  case pasteOverVisualSelection
  /// Normal `gv` -- reselect the last visual range.
  case reselectLastVisual
}

final class VimEngine {
  private(set) var mode: VimMode = .normal
  // `pendingBuffer` and the count/motion helpers are module-internal (not private)
  // so the normal-mode pending-prefix handlers can live in a VimEngine extension
  // file (VimEngineNormalPending.swift), keeping this file within its length budget.
  var pendingBuffer: String = ""
  private var countAccumulator: Int = 0
  /// Count typed BEFORE the pending prefix (`2` in `2d3w`). Vim
  /// multiplies it with the post-operator count; a single accumulator
  /// concatenated the digits (`2d3w` became 23 words).
  var pendingCount: Int = 0

  func handle(key: String, hasModifiers: Bool) -> VimAction {
    if hasModifiers { return .none }

    switch mode {
    case .insert:
      return handleInsert(key: key)
    case .normal:
      return handleNormal(key: key)
    case .visual:
      return handleVisualMode(key: key, wise: .char)
    case .visualLine:
      return handleVisualMode(key: key, wise: .line)
    }
  }

  func reset() {
    mode = .normal
    pendingBuffer = ""
    countAccumulator = 0
    pendingCount = 0
  }

  /// Sanctioned mode transition for the extension-hosted pending handlers, which
  /// cannot touch `mode`'s private setter directly from another file.
  func enterInsertMode() { mode = .insert }

  private func handleInsert(key: String) -> VimAction {
    guard key == "\u{1B}" || key == "escape" else { return .none }
    mode = .normal
    pendingBuffer = ""
    countAccumulator = 0
    pendingCount = 0
    return .switchToNormal
  }

  private func handleNormal(key: String) -> VimAction {
    // Digits accumulate counts everywhere EXCEPT after `r`, where the
    // next key is the literal replacement character (vim: `r3`).
    if key.count == 1, let ch = key.first, ch.isNumber, pendingBuffer != "r" {
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

  /// Keys that open a pending sequence: operators, prefix leaders, and
  /// the single-char replace capture.
  private static let pendingPrefixes: Set<String> = ["d", "c", "y", "g", ",", "\\", "r"]

  private func handleSingle(key: String) -> VimAction {
    if Self.pendingPrefixes.contains(key) {
      pendingBuffer = key
      // Capture the pre-operator count so post-operator digits start a
      // FRESH count that multiplies (vim: 2d3w = 6 words).
      pendingCount = countAccumulator
      countAccumulator = 0
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
    case "X": return .deleteCharBefore(count: count)
    case "D": return .deleteToEndOfLine
    case "C":
      // `C` = c$ -- change to end of line, like the D/Y caps family.
      mode = .insert
      return .applyOperator(.change, .motion(.lineEnd))
    case "Y":
      // nvim's default maps Y to y$ (not the vi yy quirk).
      return .applyOperator(.yank, .motion(.lineEnd))
    default: return lineEditAction(for: key, count: count)
    }
  }

  private func lineEditAction(for key: String, count: Int) -> VimAction? {
    switch key {
    case "p": return .pasteAfter(count: count)
    case "P": return .pasteBefore(count: count)
    case "J": return .joinLines(count: count)
    case "~": return .toggleCase(count: count)
    case "u": return .undo(count: count)
    default: return moveLinesAction(for: key, count: count)
    }
  }

  /// Shared by normal and visual mode: his mini.move `<M-j>`/`<M-k>`.
  private func moveLinesAction(for key: String, count: Int) -> VimAction? {
    switch key {
    case "<M-j>": return .moveLinesDown(count: count)
    case "<M-k>": return .moveLinesUp(count: count)
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
    case "s": return .enterWordHint
    case "S": return .enterFlash(.backward, count: count, scope: .document)
    case "f": return .enterFlash(.forward, count: count, scope: .currentLine)
    case "F": return .enterFlash(.backward, count: count, scope: .currentLine)
    case "K": return .enterLineFlash(count: count)
    default: return nil
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  func motionForKey(_ key: String, count: Int) -> Motion? {
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

  var resolvedCount: Int { max(1, countAccumulator) }

  /// Vim count semantics across an operator: count-before × count-after
  /// (each defaulting to 1).
  var pendingResolvedCount: Int { max(1, pendingCount) * max(1, countAccumulator) }

  func clearAccumulator() { countAccumulator = 0 }
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

  // MARK: - Visual modes (one handler; `wise` picks the emissions)

  /// Characterwise vs linewise visual: the SAME grammar (digits, g/\
  /// prefixes, <n>G absolute snap, motions extend, one command table)
  /// with per-wise action emissions. The old twin handlers drifted --
  /// this is the single owner.
  private enum VisualWise { case char, line }

  private func handleVisualMode(key: String, wise: VisualWise) -> VimAction {
    if !pendingBuffer.isEmpty {
      return handleVisualPending(key: key, wise: wise)
    }
    if key.count == 1, let ch = key.first, ch.isNumber {
      let digit = ch.wholeNumberValue ?? 0
      if digit > 0 || countAccumulator > 0 {
        countAccumulator = countAccumulator * 10 + digit
        return .none
      }
    }
    if key == "g" || key == "\\" {
      pendingBuffer = key
      return .none
    }
    // `<count>G` snaps the moving end to that ABSOLUTE line (vim);
    // bare `G` falls through to the documentEnd motion.
    if key == "G", countAccumulator > 0 {
      let target = countAccumulator
      clearAccumulator()
      return extendAction(.toLine(target), wise: wise)
    }

    let count = resolvedCount
    defer { clearAccumulator() }

    if let motion = motionForKey(key, count: count) {
      return extendAction(motion, wise: wise)
    }
    if let action = moveLinesAction(for: key, count: count) { return action }
    return visualCommand(for: key, wise: wise)
  }

  private func extendAction(_ motion: Motion, wise: VisualWise) -> VimAction {
    wise == .char ? .extendVisual(motion) : .extendVisualLine(motion)
  }

  private func handleVisualPending(key: String, wise: VisualWise) -> VimAction {
    let buffered = pendingBuffer
    let count = resolvedCount
    pendingBuffer = ""
    if buffered == "g", key == "g" {
      clearAccumulator()
      return extendAction(.documentStart, wise: wise)
    }
    if buffered == "\\", key == "t" {
      clearAccumulator()
      mode = .normal
      return .appendCurrentLineToTrayNote(count: count)
    }
    if buffered == "\\", key == "c" {
      clearAccumulator()
      mode = .normal
      return .appendCurrentLineToStateNote(count: count)
    }
    return .none
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func visualCommand(for key: String, wise: VisualWise) -> VimAction {
    switch key {
    case "\u{1B}", "escape":
      mode = .normal
      return .switchToNormal
    case "v":
      if wise == .line {
        mode = .visual
        return .enterVisual
      }
      mode = .normal
      return .switchToNormal
    case "V":
      if wise == .char {
        mode = .visualLine
        return .enterVisualLine
      }
      mode = .normal
      return .switchToNormal
    case "y":
      mode = .normal
      return wise == .char ? .yankVisualSelection : .yankVisualLine
    case "d", "x":
      mode = .normal
      return wise == .char ? .deleteVisualSelection : .deleteVisualLineSelection
    case "c":
      mode = .insert
      return wise == .char ? .changeVisualSelection : .changeVisualLineSelection
    case "o":
      return .swapVisualEnds
    case "p":
      mode = .normal
      return .pasteOverVisualSelection
    case "s":
      return .enterWordHint
    default:
      return .none
    }
  }

  /// Sanctioned re-entry for `gv` (the view owns the remembered range
  /// and its wise; the engine cannot know which to restore).
  func enterVisualMode(linewise: Bool) { mode = linewise ? .visualLine : .visual }
}
