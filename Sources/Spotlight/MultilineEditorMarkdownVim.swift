import AppKit

extension PlaceholderTextView {
  func replaceTextObject(_ object: TextObject, with replacement: String, switchingToInsert _: Bool) {
    guard let range = textObjectRange(object) else { return }
    if shouldChangeText(in: range, replacementString: replacement) {
      replaceCharacters(in: range, with: replacement)
      didChangeText()
    }
    setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
    notifyVimModeChanged()
    needsDisplay = true
  }

  func wrapCurrentWord(_ style: MarkdownWrapStyle) {
    guard let range = textObjectRange(.innerWord) else { return }
    wrap(range: range, style: style, trimEdgeWhitespace: false)
  }

  func wrapSelection(_ style: MarkdownWrapStyle) {
    let range = selectedRange
    guard range.length > 0 else { return }
    wrap(range: range, style: style, trimEdgeWhitespace: true)
    visualLineAnchor = nil
    visualLineCaret = nil
    notifyVimModeChanged()
  }

  private func wrap(range: NSRange, style: MarkdownWrapStyle, trimEdgeWhitespace: Bool) {
    let nsString = string as NSString
    guard range.location >= 0, range.location + range.length <= nsString.length else { return }
    let raw = nsString.substring(with: range)
    let wrapped = wrappedMarkdownText(raw, style: style, trimEdgeWhitespace: trimEdgeWhitespace)
    if shouldChangeText(in: range, replacementString: wrapped) {
      replaceCharacters(in: range, with: wrapped)
      didChangeText()
    }
    setSelectedRange(NSRange(location: range.location + (wrapped as NSString).length, length: 0))
    needsDisplay = true
  }

  private func wrappedMarkdownText(
    _ text: String,
    style: MarkdownWrapStyle,
    trimEdgeWhitespace: Bool
  ) -> String {
    let markers = markdownMarkers(for: style)
    guard trimEdgeWhitespace else { return markers.before + text + markers.after }
    let strippedNewlines = text.replacingOccurrences(of: #"\n+$"#, with: "", options: .regularExpression)
    let leading = strippedNewlines.prefix { $0 == " " || $0 == "\t" }
    let trailing = strippedNewlines.reversed().prefix { $0 == " " || $0 == "\t" }.reversed()
    let coreStart = strippedNewlines.index(strippedNewlines.startIndex, offsetBy: leading.count)
    let coreEnd = strippedNewlines.index(strippedNewlines.endIndex, offsetBy: -trailing.count)
    guard coreStart <= coreEnd else { return markers.before + strippedNewlines + markers.after }
    let core = strippedNewlines[coreStart..<coreEnd]
    return String(leading) + markers.before + String(core) + markers.after + String(trailing)
  }

  private func markdownMarkers(for style: MarkdownWrapStyle) -> (before: String, after: String) {
    switch style {
    case .bold: return ("**", "**")
    case .italic: return ("*", "*")
    }
  }

  private func textObjectRange(_ object: TextObject) -> NSRange? {
    switch object {
    case .innerWord:
      return innerWordRange()
    }
  }

  private func innerWordRange() -> NSRange? {
    let nsString = string as NSString
    guard nsString.length > 0 else { return nil }
    var cursor = min(selectedRange.location, max(0, nsString.length - 1))
    if !isWordCharacter(nsString.character(at: cursor)), cursor > 0 {
      cursor -= 1
    }
    guard isWordCharacter(nsString.character(at: cursor)) else { return nil }
    var start = cursor
    while start > 0, isWordCharacter(nsString.character(at: start - 1)) {
      start -= 1
    }
    var end = cursor + 1
    while end < nsString.length, isWordCharacter(nsString.character(at: end)) {
      end += 1
    }
    return NSRange(location: start, length: end - start)
  }

  private func isWordCharacter(_ ch: unichar) -> Bool {
    if ch == 0x5F { return true }
    guard let scalar = UnicodeScalar(ch) else { return false }
    return CharacterSet.alphanumerics.contains(scalar)
  }
}
