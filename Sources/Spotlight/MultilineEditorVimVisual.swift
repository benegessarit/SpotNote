import AppKit

extension PlaceholderTextView {
  func executeVisualVimAction(_ action: VimAction) -> Bool {
    switch action {
    case .enterVisual:
      enterVisualMode()
    case .extendVisual(let motion):
      extendVisual(by: motion)
    case .yankVisualSelection:
      yankVisualSelection()
    case .deleteVisualSelection:
      deleteVisualSelection(switchingToInsert: false)
    case .changeVisualSelection:
      deleteVisualSelection(switchingToInsert: true)
    default:
      return false
    }
    return true
  }

  private func enterVisualMode() {
    let length = (string as NSString).length
    let anchor = min(visualLineAnchor ?? selectedRange.location, length)
    let caret = min(visualLineCaret ?? anchor, length)
    visualLineAnchor = nil
    visualLineCaret = nil
    visualAnchor = anchor
    visualCaret = caret
    setSelectedRange(characterwiseRange(from: anchor, to: caret))
    notifyVimModeChanged()
    needsDisplay = true
  }

  private func extendVisual(by motion: Motion) {
    guard let anchor = visualAnchor else { return }
    let nsString = string as NSString
    let length = nsString.length
    let caretBefore = min(visualCaret ?? anchor, length)

    setSelectedRange(NSRange(location: caretBefore, length: 0))
    executeMotion(motion)
    let rawCaretAfter = min(selectedRange.location, length)
    let caretAfter = visualCaretLocation(rawCaretAfter, for: motion, in: nsString)
    visualCaret = caretAfter
    setSelectedRange(characterwiseRange(from: anchor, to: caretAfter))
    scrollRangeToVisible(NSRange(location: caretAfter, length: 0))
    needsDisplay = true
  }

  private func characterwiseRange(from anchor: Int, to caret: Int) -> NSRange {
    let length = (string as NSString).length
    guard length > 0 else { return NSRange(location: 0, length: 0) }
    let clampedAnchor = min(max(0, anchor), length)
    let clampedCaret = min(max(0, caret), length)
    if clampedAnchor == length, clampedCaret == length {
      return NSRange(location: length, length: 0)
    }
    let start = min(clampedAnchor, clampedCaret)
    let end = min(max(clampedAnchor, clampedCaret) + 1, length)
    return NSRange(location: start, length: max(0, end - start))
  }

  private func visualCaretLocation(_ location: Int, for motion: Motion, in nsString: NSString) -> Int {
    guard case .lineEnd = motion else { return location }
    guard nsString.length > 0 else { return 0 }
    let probe = min(location, max(0, nsString.length - 1))
    let line = nsString.lineRange(for: NSRange(location: probe, length: 0))
    var contentEnd = line.location + line.length
    while contentEnd > line.location {
      let ch = nsString.character(at: contentEnd - 1)
      guard ch == 0x0A || ch == 0x0D else { break }
      contentEnd -= 1
    }
    return contentEnd > line.location ? contentEnd - 1 : line.location
  }

  private func yankVisualSelection() {
    let nsString = string as NSString
    let range = selectedRange
    if range.length > 0, range.location + range.length <= nsString.length {
      let text = nsString.substring(with: range)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
    }
    exitVisualSelection(restoreCaretTo: visualCaret ?? range.location)
  }

  private func deleteVisualSelection(switchingToInsert: Bool) {
    let range = selectedRange
    let restorePoint = range.location
    if range.length > 0, shouldChangeText(in: range, replacementString: "") {
      replaceCharacters(in: range, with: "")
      didChangeText()
    }
    visualAnchor = nil
    visualCaret = nil
    setSelectedRange(NSRange(location: min(restorePoint, (string as NSString).length), length: 0))
    notifyVimModeChanged()
    _ = switchingToInsert
    needsDisplay = true
  }

  private func exitVisualSelection(restoreCaretTo location: Int) {
    visualAnchor = nil
    visualCaret = nil
    let clamped = min(location, (string as NSString).length)
    setSelectedRange(NSRange(location: clamped, length: 0))
    notifyVimModeChanged()
    needsDisplay = true
  }
}
