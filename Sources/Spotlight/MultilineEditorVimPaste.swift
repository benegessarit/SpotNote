import AppKit

extension PlaceholderTextView {
  func executeVimPasteAfter(count: Int) {
    guard let text = vimPasteboard.string(forType: .string), !text.isEmpty else { return }
    let pasteText = String(repeating: text, count: max(1, count))
    if isLinewisePaste(text) {
      pasteLinewiseAfterCurrentLine(pasteText)
    } else {
      pasteCharacterwiseAfterCursor(pasteText)
    }
  }

  private func pasteCharacterwiseAfterCursor(_ text: String) {
    let nsString = string as NSString
    let insertion = nsString.length == 0 ? 0 : min(selectedRange.location + 1, nsString.length)
    performVimPaste(text, at: insertion)
    let pastedLength = (text as NSString).length
    let caret = pastedLength > 0 ? insertion + pastedLength - 1 : insertion
    setSelectedRange(NSRange(location: min(caret, (string as NSString).length), length: 0))
    needsDisplay = true
  }

  private func pasteLinewiseAfterCurrentLine(_ text: String) {
    let nsString = string as NSString
    guard nsString.length > 0 else {
      performVimPaste(text, at: 0)
      setSelectedRange(NSRange(location: 0, length: 0))
      needsDisplay = true
      return
    }
    let cursor = min(selectedRange.location, nsString.length)
    let currentLine = nsString.lineRange(for: NSRange(location: cursor, length: 0))
    if isVisiblyEmptyLine(currentLine, in: nsString) {
      performVimPaste(text, replacing: currentLine)
      setSelectedRange(NSRange(location: min(currentLine.location, (string as NSString).length), length: 0))
      needsDisplay = true
      return
    }
    let insertion = currentLine.location + currentLine.length
    let prefix = currentLineEndsWithNewline(currentLine, in: nsString) ? "" : "\n"
    performVimPaste(prefix + text, at: insertion)
    let pastedStart = insertion + (prefix as NSString).length
    setSelectedRange(NSRange(location: min(pastedStart, (string as NSString).length), length: 0))
    needsDisplay = true
  }

  private func performVimPaste(_ text: String, at insertion: Int) {
    performVimPaste(text, replacing: NSRange(location: insertion, length: 0))
  }

  private func performVimPaste(_ text: String, replacing range: NSRange) {
    isPasting = true
    defer { isPasting = false }
    guard shouldChangeText(in: range, replacementString: text) else { return }
    replaceCharacters(in: range, with: text)
    didChangeText()
  }

  private func isLinewisePaste(_ text: String) -> Bool {
    text.hasSuffix("\n") || text.hasSuffix("\r")
  }

  private func currentLineEndsWithNewline(_ line: NSRange, in nsString: NSString) -> Bool {
    guard line.length > 0 else { return false }
    let last = nsString.character(at: line.location + line.length - 1)
    return last == 0x0A || last == 0x0D
  }

  private func isVisiblyEmptyLine(_ line: NSRange, in nsString: NSString) -> Bool {
    nsString.lineContentEnd(of: line) == line.location
  }
}
