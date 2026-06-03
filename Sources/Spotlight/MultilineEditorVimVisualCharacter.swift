import AppKit

extension PlaceholderTextView {
  func executeVisualCharacterAction(_ action: VimAction) -> Bool {
    switch action {
    case .enterVisualCharacter:
      enterVisualCharacterMode()
    case .extendVisualCharacter(let motion):
      extendVisualCharacter(by: motion)
    case .yankVisualCharacter:
      yankVisualCharacterSelection()
    case .deleteVisualCharacterSelection:
      deleteVisualCharacterSelection(switchingToInsert: false)
    case .changeVisualCharacterSelection:
      deleteVisualCharacterSelection(switchingToInsert: true)
    default:
      return false
    }
    return true
  }

  private func enterVisualCharacterMode() {
    let nsString = string as NSString
    let anchor = visualCharacterLocation(selectedRange.location, in: nsString)
    visualCharacterAnchor = anchor
    visualCharacterCaret = anchor
    setSelectedRange(characterwiseRange(from: anchor, to: anchor, in: nsString))
    notifyVimModeChanged()
    needsDisplay = true
  }

  private func extendVisualCharacter(by motion: Motion) {
    guard let anchor = visualCharacterAnchor else { return }
    let nsString = string as NSString
    let caretBefore = visualCharacterCaret ?? anchor

    setSelectedRange(NSRange(location: caretBefore, length: 0))
    executeMotion(motion)

    let caretAfter = visualCharacterLocation(selectedRange.location, in: nsString)
    visualCharacterCaret = caretAfter
    setSelectedRange(characterwiseRange(from: anchor, to: caretAfter, in: nsString))
    scrollRangeToVisible(NSRange(location: caretAfter, length: 0))
    needsDisplay = true
  }

  private func yankVisualCharacterSelection() {
    let nsString = string as NSString
    let range = selectedRange
    if range.length > 0, range.location + range.length <= nsString.length {
      let text = nsString.substring(with: range)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
    }
    exitVisualCharacterSelection(restoreCaretTo: range.location)
  }

  private func deleteVisualCharacterSelection(switchingToInsert _: Bool) {
    let range = selectedRange
    let restorePoint = range.location
    if range.length > 0, shouldChangeText(in: range, replacementString: "") {
      replaceCharacters(in: range, with: "")
      didChangeText()
    }
    visualCharacterAnchor = nil
    visualCharacterCaret = nil
    let clamped = min(restorePoint, (string as NSString).length)
    setSelectedRange(NSRange(location: clamped, length: 0))
    notifyVimModeChanged()
    needsDisplay = true
  }

  private func exitVisualCharacterSelection(restoreCaretTo location: Int) {
    visualCharacterAnchor = nil
    visualCharacterCaret = nil
    let clamped = min(location, (string as NSString).length)
    setSelectedRange(NSRange(location: clamped, length: 0))
    notifyVimModeChanged()
    needsDisplay = true
  }

  private func characterwiseRange(from anchor: Int, to caret: Int, in nsString: NSString) -> NSRange {
    guard nsString.length > 0 else { return NSRange(location: 0, length: 0) }
    let start = min(anchor, caret)
    let end = max(anchor, caret) + 1
    return NSRange(location: start, length: max(0, end - start))
  }

  private func visualCharacterLocation(_ location: Int, in nsString: NSString) -> Int {
    guard nsString.length > 0 else { return 0 }
    let clamped = min(max(0, location), nsString.length - 1)
    if clamped > 0, isLineBreak(nsString.character(at: clamped)) { return clamped - 1 }
    return clamped
  }

  private func isLineBreak(_ ch: unichar) -> Bool {
    ch == 0x0A || ch == 0x0D
  }
}
