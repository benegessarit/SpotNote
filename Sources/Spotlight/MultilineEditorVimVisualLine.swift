import AppKit

extension PlaceholderTextView {
  func executeVisualLineAction(_ action: VimAction) -> Bool {
    switch action {
    case .enterVisualLine:
      enterVisualLineMode()
    case .extendVisualLine(let motion):
      extendVisualLine(by: motion)
    case .yankVisualLine:
      yankVisualLineSelection()
    case .deleteVisualLineSelection:
      deleteVisualLineSelection(switchingToInsert: false)
    case .changeVisualLineSelection:
      deleteVisualLineSelection(switchingToInsert: true)
    default: return false
    }
    return true
  }

  // MARK: - Visual line

  /// Captures the anchor at the current caret line and immediately
  /// selects the whole line so the user sees the mode is active.
  private func enterVisualLineMode() {
    let anchor = selectedRange.location
    visualCharacterAnchor = nil
    visualCharacterCaret = nil
    visualLineAnchor = anchor
    visualLineCaret = anchor
    setSelectedRange(linewiseRange(from: anchor, to: anchor))
    notifyVimModeChanged()
    needsDisplay = true
  }

  /// Re-runs `motion` against the live visual-line caret (which is
  /// tracked separately from `selectedRange` so it can sit above or
  /// below the anchor independently). After the motion we re-snap the
  /// selection to full-line boundaries between anchor and new caret.
  private func extendVisualLine(by motion: Motion) {
    guard let anchor = visualLineAnchor else { return }
    let nsString = string as NSString
    let length = nsString.length
    let caretBefore = min(visualLineCaret ?? anchor, length)

    setSelectedRange(NSRange(location: caretBefore, length: 0))
    executeMotion(motion)
    let caretAfter = min(selectedRange.location, length)
    visualLineCaret = caretAfter
    setSelectedRange(linewiseRange(from: anchor, to: caretAfter))
    scrollRangeToVisible(NSRange(location: caretAfter, length: 0))
    needsDisplay = true
  }

  private func linewiseRange(from anchor: Int, to caret: Int) -> NSRange {
    let nsString = string as NSString
    let lo = min(anchor, caret)
    let hi = max(anchor, caret)
    let lower = nsString.lineRange(for: NSRange(location: lo, length: 0))
    let upper = nsString.lineRange(for: NSRange(location: hi, length: 0))
    let start = lower.location
    let end = upper.location + upper.length
    return NSRange(location: start, length: max(0, end - start))
  }

  /// `y` in visual line mode -- copies the selection (with the trailing
  /// newline preserved, matching real vim) and exits to normal.
  private func yankVisualLineSelection() {
    let nsString = string as NSString
    let range = selectedRange
    if range.length > 0, range.length <= nsString.length {
      let text = nsString.substring(with: range)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
    }
    exitVisualLineSelection(restoreCaretTo: range.location)
  }

  /// `d` / `c` in visual line mode -- deletes the selection and either
  /// returns to normal (delete) or switches to insert (change).
  private func deleteVisualLineSelection(switchingToInsert: Bool) {
    let range = selectedRange
    let restorePoint = range.location
    if range.length > 0, shouldChangeText(in: range, replacementString: "") {
      replaceCharacters(in: range, with: "")
      didChangeText()
    }
    visualLineAnchor = nil
    visualLineCaret = nil
    setSelectedRange(NSRange(location: min(restorePoint, (string as NSString).length), length: 0))
    notifyVimModeChanged()
    _ = switchingToInsert  // mode is already updated by the engine
    needsDisplay = true
  }

  private func exitVisualLineSelection(restoreCaretTo location: Int) {
    visualLineAnchor = nil
    visualLineCaret = nil
    let clamped = min(location, (string as NSString).length)
    setSelectedRange(NSRange(location: clamped, length: 0))
    notifyVimModeChanged()
    needsDisplay = true
  }

}
