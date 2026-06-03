import AppKit

extension PlaceholderTextView {
  func replaceTextObject(_ object: TextObject, with replacement: String, switchingToInsert _: Bool) {
    guard let range = textObjectRange(object) else { return }
    if shouldChangeText(in: range, replacementString: replacement) {
      replaceCharacters(in: range, with: replacement)
      didChangeText()
    }
    setSelectedRange(
      NSRange(location: range.location + (replacement as NSString).length, length: 0)
    )
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
    visualCharacterAnchor = nil
    visualCharacterCaret = nil
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
    let strippedNewlines = text.replacingOccurrences(
      of: #"\n+$"#,
      with: "",
      options: .regularExpression
    )
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
    case .aroundWord:
      return aroundRange(inner: innerWordRange())
    case .innerSentence:
      return innerSentenceRange()
    case .aroundSentence:
      return aroundRange(inner: innerSentenceRange())
    case .innerParagraph:
      return paragraphRange()
    case .aroundParagraph:
      return aroundParagraphRange()
    }
  }

  private func innerWordRange() -> NSRange? {
    let nsString = string as NSString
    guard nsString.length > 0 else { return nil }
    var cursor = clampedCursor(in: nsString)
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

  private func innerSentenceRange() -> NSRange? {
    let nsString = string as NSString
    guard nsString.length > 0, let paragraph = paragraphContentRange() else { return nil }
    let cursor = min(max(clampedCursor(in: nsString), paragraph.location), rangeEnd(paragraph) - 1)
    let bounds = sentenceLineBounds(cursor, nsString, paragraph)
    let raw = NSRange(
      location: sentenceStart(containing: cursor, in: nsString, bounds: bounds),
      length: 0
    )
    let end = sentenceEnd(containing: cursor, in: nsString, bounds: bounds)
    return trimmedRange(NSRange(location: raw.location, length: end - raw.location), in: nsString)
  }

  private func paragraphRange() -> NSRange? {
    let nsString = string as NSString
    guard nsString.length > 0, let range = rawParagraphRange(in: nsString) else { return nil }
    return containsNonWhitespace(range, in: nsString) ? range : nil
  }

  private func paragraphContentRange() -> NSRange? {
    let nsString = string as NSString
    guard let range = paragraphRange() else { return nil }
    return trimmedRange(range, in: nsString)
  }

  private func rawParagraphRange(in nsString: NSString) -> NSRange? {
    let cursor = clampedCursor(in: nsString)
    let separators = paragraphSeparators(in: nsString)
    let start = separators.last { rangeEnd($0) <= cursor }.map(rangeEnd) ?? 0
    let end = separators.first { $0.location > cursor }?.location ?? nsString.length
    return NSRange(location: start, length: end - start)
  }

  private func aroundParagraphRange() -> NSRange? {
    let nsString = string as NSString
    guard let inner = paragraphRange() else { return nil }
    let separators = paragraphSeparators(in: nsString)
    if let following = separators.first(where: { $0.location == rangeEnd(inner) }) {
      return NSRange(location: inner.location, length: inner.length + following.length)
    }
    if let previous = separators.last(where: { rangeEnd($0) == inner.location }) {
      return NSRange(location: previous.location, length: previous.length + inner.length)
    }
    return inner
  }

  private func aroundRange(inner: NSRange?) -> NSRange? {
    let nsString = string as NSString
    guard let inner else { return nil }
    let following = whitespaceRun(from: rangeEnd(inner), forward: true, in: nsString)
    if following.length > 0 {
      return NSRange(location: inner.location, length: inner.length + following.length)
    }
    let previous = whitespaceRun(from: inner.location - 1, forward: false, in: nsString)
    return NSRange(location: previous.location, length: previous.length + inner.length)
  }

  private func sentenceStart(containing cursor: Int, in nsString: NSString, bounds: NSRange) -> Int {
    var index = cursor
    while index > bounds.location {
      index -= 1
      guard isSentenceBoundary(index, nsString, limit: rangeEnd(bounds)) else {
        continue
      }
      let boundaryEnd = afterSentenceTerminator(index, nsString, limit: rangeEnd(bounds))
      if cursor >= boundaryEnd {
        return firstContent(after: index, in: nsString, limit: rangeEnd(bounds))
      }
    }
    return bounds.location
  }

  private func sentenceEnd(containing cursor: Int, in nsString: NSString, bounds: NSRange) -> Int {
    if let closingEnd = sentenceEndForClosingPunctuation(
      containing: cursor,
      in: nsString,
      bounds: bounds
    ) {
      return closingEnd
    }
    var index = cursor
    while index < rangeEnd(bounds) {
      if isSentenceBoundary(index, nsString, limit: rangeEnd(bounds)) {
        return afterSentenceTerminator(index, nsString, limit: rangeEnd(bounds))
      }
      index += 1
    }
    return rangeEnd(bounds)
  }

  private func sentenceEndForClosingPunctuation(
    containing cursor: Int,
    in nsString: NSString,
    bounds: NSRange
  ) -> Int? {
    guard cursor < rangeEnd(bounds), isSentenceClosingPunctuation(nsString.character(at: cursor))
    else { return nil }
    var index = cursor
    while index >= bounds.location, isSentenceClosingPunctuation(nsString.character(at: index)) {
      index -= 1
    }
    guard index >= bounds.location,
      isSentenceBoundary(index, nsString, limit: rangeEnd(bounds))
    else {
      return nil
    }
    let end = afterSentenceTerminator(index, nsString, limit: rangeEnd(bounds))
    return cursor < end ? end : nil
  }

  private func sentenceLineBounds(_ cursor: Int, _ nsString: NSString, _ paragraph: NSRange) -> NSRange {
    let line = logicalLineRange(cursor, nsString, paragraph)
    return containsNonWhitespace(line, in: nsString) ? line : paragraph
  }

  private func logicalLineRange(_ cursor: Int, _ nsString: NSString, _ bounds: NSRange) -> NSRange {
    var start = cursor
    while start > bounds.location, nsString.character(at: start - 1) != 0x0A {
      start -= 1
    }
    var end = cursor
    while end < rangeEnd(bounds), nsString.character(at: end) != 0x0A {
      end += 1
    }
    return NSRange(location: start, length: end - start)
  }

  private func firstContent(after index: Int, in nsString: NSString, limit: Int) -> Int {
    var location = afterSentenceTerminator(index, nsString, limit: limit)
    while location < limit, isWhitespace(nsString.character(at: location)) {
      location += 1
    }
    return location
  }

  private func afterSentenceTerminator(_ index: Int, _ nsString: NSString, limit: Int) -> Int {
    var location = index + 1
    while location < limit, isSentenceClosingPunctuation(nsString.character(at: location)) {
      location += 1
    }
    return location
  }

  private func paragraphSeparators(in nsString: NSString) -> [NSRange] {
    let text = nsString as String
    let fullRange = NSRange(location: 0, length: nsString.length)
    let regex = try? NSRegularExpression(pattern: #"\n[ \t]*\n+"#)
    return regex?.matches(in: text, range: fullRange).map(\.range) ?? []
  }

  private func trimmedRange(_ range: NSRange, in nsString: NSString) -> NSRange? {
    var start = range.location
    var end = rangeEnd(range)
    while start < end, isWhitespace(nsString.character(at: start)) { start += 1 }
    while end > start, isWhitespace(nsString.character(at: end - 1)) { end -= 1 }
    guard end > start else { return nil }
    return NSRange(location: start, length: end - start)
  }

  private func containsNonWhitespace(_ range: NSRange, in nsString: NSString) -> Bool {
    guard range.location >= 0, rangeEnd(range) <= nsString.length else { return false }
    for index in range.location..<rangeEnd(range) where !isWhitespace(nsString.character(at: index)) {
      return true
    }
    return false
  }

  private func whitespaceRun(from index: Int, forward: Bool, in nsString: NSString) -> NSRange {
    guard index >= 0, index < nsString.length else {
      return NSRange(location: max(0, index), length: 0)
    }
    var start = index
    var end = index + 1
    guard isWhitespace(nsString.character(at: index)) else {
      return NSRange(location: end, length: 0)
    }
    if forward {
      while end < nsString.length, isWhitespace(nsString.character(at: end)) { end += 1 }
    } else {
      while start > 0, isWhitespace(nsString.character(at: start - 1)) { start -= 1 }
    }
    return NSRange(location: start, length: end - start)
  }

  private func clampedCursor(in nsString: NSString) -> Int {
    min(selectedRange.location, max(0, nsString.length - 1))
  }

  private func rangeEnd(_ range: NSRange) -> Int {
    range.location + range.length
  }

  private func isWordCharacter(_ ch: unichar) -> Bool {
    if ch == 0x5F { return true }
    guard let scalar = UnicodeScalar(ch) else { return false }
    return CharacterSet.alphanumerics.contains(scalar)
  }

  private func isWhitespace(_ ch: unichar) -> Bool {
    guard let scalar = UnicodeScalar(ch) else { return false }
    return CharacterSet.whitespacesAndNewlines.contains(scalar)
  }

  private func isSentenceBoundary(_ index: Int, _ nsString: NSString, limit: Int) -> Bool {
    guard isSentenceTerminator(nsString.character(at: index)) else { return false }
    let afterTerminator = afterSentenceTerminator(index, nsString, limit: limit)
    if afterTerminator >= limit { return true }
    return isSentenceBoundaryWhitespace(nsString.character(at: afterTerminator))
  }

  private func isSentenceTerminator(_ ch: unichar) -> Bool {
    ch == 0x2E || ch == 0x21 || ch == 0x3F
  }

  private func isSentenceBoundaryWhitespace(_ ch: unichar) -> Bool {
    switch ch {
    case 0x09, 0x0A, 0x0D, 0x20:
      return true
    default:
      return false
    }
  }

  private func isSentenceClosingPunctuation(_ ch: unichar) -> Bool {
    switch ch {
    case 0x22, 0x27, 0x29, 0x5D, 0x7D, 0x2019, 0x201D:
      return true
    default:
      return false
    }
  }
}
