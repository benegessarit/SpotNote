import AppKit

/// Normal-mode single-key editing commands from the caps/tilde family:
/// `J` join, `~` toggle case, `r` replace char, `X` delete-back. All are
/// line-scoped like vim -- none of them crosses a newline except `J`,
/// whose whole job is to remove one.
extension PlaceholderTextView {
  /// `J`: replace the newline (plus the next line's leading indent) with
  /// a single space; with a count, vim joins count lines total, so the
  /// join runs max(1, count-1) times but at least once. Caret lands on
  /// the join space, like vim.
  func executeJoinLines(count: Int) {
    let joins = max(1, count - 1)
    var joinPoint: Int?
    for _ in 0..<joins {
      guard let point = joinNextLineUp() else { break }
      joinPoint = point
    }
    if let joinPoint {
      setSelectedRange(NSRange(location: joinPoint, length: 0))
    }
    needsDisplay = true
  }

  private func joinNextLineUp() -> Int? {
    let nsString = string as NSString
    let cursor = min(selectedRange.location, nsString.length)
    let line = nsString.lineRange(for: NSRange(location: cursor, length: 0))
    let contentEnd = nsString.lineContentEnd(of: line)
    let lineEnd = line.location + line.length
    // No trailing newline = last line; nothing to join.
    guard lineEnd > contentEnd else { return nil }
    var indentEnd = lineEnd
    while indentEnd < nsString.length {
      let ch = nsString.character(at: indentEnd)
      guard ch == 0x20 || ch == 0x09 else { break }
      indentEnd += 1
    }
    let removed = NSRange(location: contentEnd, length: indentEnd - contentEnd)
    // vim inserts one space unless the joined line is empty.
    let separator =
      contentEnd > line.location && indentEnd < nsString.length
        && nsString.character(at: indentEnd) != 0x0A ? " " : ""
    guard shouldChangeText(in: removed, replacementString: separator) else { return nil }
    replaceCharacters(in: removed, with: separator)
    didChangeText()
    return contentEnd
  }

  /// `~`: toggle the case of count characters, advancing over each;
  /// stops at the line end (vim never wraps `~`).
  func executeToggleCase(count: Int) {
    let nsString = string as NSString
    let cursor = min(selectedRange.location, nsString.length)
    let line = nsString.lineRange(for: NSRange(location: cursor, length: 0))
    let contentEnd = nsString.lineContentEnd(of: line)
    let end = min(cursor + count, contentEnd)
    guard end > cursor else { return }
    let range = NSRange(location: cursor, length: end - cursor)
    let original = nsString.substring(with: range)
    let toggled = String(
      original.map { ch -> Character in
        if ch.isUppercase { return Character(ch.lowercased()) }
        if ch.isLowercase { return Character(ch.uppercased()) }
        return ch
      }
    )
    guard shouldChangeText(in: range, replacementString: toggled) else { return }
    replaceCharacters(in: range, with: toggled)
    didChangeText()
    setSelectedRange(NSRange(location: min(end, (string as NSString).length), length: 0))
    needsDisplay = true
  }

  /// `r<char>`: overwrite count characters with the typed one, caret on
  /// the last replacement. vim aborts the whole command when fewer than
  /// count characters remain on the line -- so do we.
  func executeReplaceChar(_ replacement: String, count: Int) {
    let nsString = string as NSString
    let cursor = min(selectedRange.location, nsString.length)
    let line = nsString.lineRange(for: NSRange(location: cursor, length: 0))
    let contentEnd = nsString.lineContentEnd(of: line)
    guard cursor + count <= contentEnd else { return }
    let range = NSRange(location: cursor, length: count)
    let text = String(repeating: replacement, count: count)
    guard shouldChangeText(in: range, replacementString: text) else { return }
    replaceCharacters(in: range, with: text)
    didChangeText()
    let caret = cursor + (text as NSString).length - (replacement as NSString).length
    setSelectedRange(NSRange(location: min(caret, (string as NSString).length), length: 0))
    needsDisplay = true
  }

  /// `X`: delete up to count characters before the caret, never past the
  /// line start.
  func executeDeleteCharBefore(count: Int) {
    let nsString = string as NSString
    let cursor = min(selectedRange.location, nsString.length)
    let line = nsString.lineRange(for: NSRange(location: cursor, length: 0))
    let start = max(line.location, cursor - count)
    guard cursor > start else { return }
    insertText("", replacementRange: NSRange(location: start, length: cursor - start))
    needsDisplay = true
  }
}
