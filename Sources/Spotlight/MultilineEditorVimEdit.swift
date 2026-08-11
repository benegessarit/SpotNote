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

  /// `x`: delete up to count characters at/after the caret.
  func executeDeleteChar(_ count: Int) {
    let nsString = string as NSString
    let cursor = selectedRange.location
    let end = min(cursor + count, nsString.length)
    guard end > cursor else { return }
    insertText("", replacementRange: NSRange(location: cursor, length: end - cursor))
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

  /// `<M-j>`/`<M-k>` (his mini.move): slide the caret's line -- or the
  /// line block covering the visual selection -- down/up `count` steps,
  /// clamping silently at the buffer edges. Caret (and in visual mode
  /// the whole selection plus its anchors) rides along, offsets inside
  /// the block preserved, so repeats keep working on the same lines.
  func executeMoveLines(down: Bool, count: Int) {
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    let selection = selectedRange
    var block = nsString.lineRange(for: selection)
    let startOfBlock = block.location
    let caretOffset = selection.location - startOfBlock
    let selectionLength = selection.length
    let anchors = [visualAnchor, visualCaret, visualLineAnchor, visualLineCaret]
      .map { $0.map { $0 - startOfBlock } }
    var moved = false
    for _ in 0..<max(1, count) {
      guard down ? moveBlockDownOnce(&block) : moveBlockUpOnce(&block) else { break }
      moved = true
    }
    guard moved else { return }
    let limit = (string as NSString).length
    let newStart = min(block.location + caretOffset, limit)
    setSelectedRange(NSRange(location: newStart, length: min(selectionLength, limit - newStart)))
    visualAnchor = anchors[0].map { min(block.location + $0, limit) }
    visualCaret = anchors[1].map { min(block.location + $0, limit) }
    visualLineAnchor = anchors[2].map { min(block.location + $0, limit) }
    visualLineCaret = anchors[3].map { min(block.location + $0, limit) }
    scrollRangeToVisible(selectedRange)
    needsDisplay = true
  }

  /// One down-step: the line below the block hops over it. The block
  /// always ends in a newline here (a line exists below); when the
  /// hopping line is the document tail without one, it donates the
  /// block's newline instead (text length is conserved).
  private func moveBlockDownOnce(_ block: inout NSRange) -> Bool {
    let nsString = string as NSString
    let nextStart = NSMaxRange(block)
    guard nextStart < nsString.length else { return false }
    let next = nsString.lineRange(for: NSRange(location: nextStart, length: 0))
    var nextText = nsString.substring(with: next)
    var blockText = nsString.substring(with: block)
    var newLength = block.length
    if !nextText.hasSuffix("\n") {
      nextText += "\n"
      blockText = String(blockText.dropLast())
      newLength -= 1
    }
    let span = NSRange(location: block.location, length: block.length + next.length)
    guard replaceForLineMove(span, with: nextText + blockText) else { return false }
    block = NSRange(location: block.location + (nextText as NSString).length, length: newLength)
    return true
  }

  /// One up-step, mirror of the down-step: the line above hops below the
  /// block; a tail block without a newline borrows the hopping line's.
  private func moveBlockUpOnce(_ block: inout NSRange) -> Bool {
    let nsString = string as NSString
    guard block.location > 0 else { return false }
    let prev = nsString.lineRange(for: NSRange(location: block.location - 1, length: 0))
    var blockText = nsString.substring(with: block)
    var prevText = nsString.substring(with: prev)
    var newLength = block.length
    if !blockText.hasSuffix("\n") {
      blockText += "\n"
      prevText = String(prevText.dropLast())
      newLength += 1
    }
    let span = NSRange(location: prev.location, length: prev.length + block.length)
    guard replaceForLineMove(span, with: blockText + prevText) else { return false }
    block = NSRange(location: prev.location, length: newLength)
    return true
  }

  private func replaceForLineMove(_ span: NSRange, with replacement: String) -> Bool {
    guard shouldChangeText(in: span, replacementString: replacement) else { return false }
    replaceCharacters(in: span, with: replacement)
    didChangeText()
    return true
  }
}
