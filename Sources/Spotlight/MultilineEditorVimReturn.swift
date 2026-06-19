import AppKit

extension PlaceholderTextView {
  func handleVimReturnKey(_ event: NSEvent, engine: VimEngine) -> Bool {
    guard event.keyCode == 36 || event.keyCode == 76 else { return false }
    if engine.mode == .insert {
      insertNewline(nil)
      return true
    }
    guard engine.mode == .normal || engine.mode == .visual || engine.mode == .visualLine else {
      return false
    }
    toggleMarkdownBulletForVimReturn(engine: engine)
    return true
  }

  private func toggleMarkdownBulletForVimReturn(engine: VimEngine) {
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    let selection = selectedRange
    let ranges = vimReturnLineRanges(for: selection, in: nsString)
    let lines = ranges.compactMap { vimReturnLineContent(in: $0, text: nsString) }
      .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    guard !lines.isEmpty else { return }

    if let markerCycleEdits = vimReturnMarkerCycleEdits(for: lines) {
      let targetCaret = vimReturnMarkerCycleCaret(after: markerCycleEdits, originalSelection: selection)
      applyVimReturnLineEdits(markerCycleEdits, targetCaret: targetCaret, engine: engine)
      return
    }

    let removingBullets = lines.allSatisfy {
      MarkdownOutline.continuationPrefix(in: $0.text) != nil
    }
    let edits = lines.compactMap { line -> VimReturnLineEdit? in
      let replacement =
        removingBullets
        ? vimReturnLineRemovingBullet(line.text)
        : vimReturnLineAddingBullet(line.text)
      guard let replacement, replacement != line.text else { return nil }
      return VimReturnLineEdit(range: line.range, original: line.text, replacement: replacement)
    }
    let targetCaret = vimReturnCaretLocation(
      after: edits,
      originalSelection: selection,
      removingBullets: removingBullets
    )
    applyVimReturnLineEdits(edits, targetCaret: targetCaret, engine: engine)
  }

  private func applyVimReturnLineEdits(
    _ edits: [VimReturnLineEdit],
    targetCaret: Int,
    engine: VimEngine
  ) {
    guard !edits.isEmpty else { return }
    for edit in edits.reversed() {
      guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
      replaceCharacters(in: edit.range, with: edit.replacement)
    }
    didChangeText()
    exitVisualModeForReturnToggle(engine: engine)
    let clampedCaret = min(max(0, targetCaret), (string as NSString).length)
    setSelectedRange(NSRange(location: clampedCaret, length: 0))
    scrollRangeToVisible(NSRange(location: clampedCaret, length: 0))
    needsDisplay = true
  }

  private func vimReturnMarkerCycleEdits(for lines: [VimReturnLine]) -> [VimReturnLineEdit]? {
    let edits = lines.compactMap { line -> VimReturnLineEdit? in
      guard let replacement = MarkdownOutline.standaloneMarkerCycleReplacement(for: line.text) else {
        return nil
      }
      return VimReturnLineEdit(range: line.range, original: line.text, replacement: replacement)
    }
    return edits.count == lines.count ? edits : nil
  }

  private func vimReturnMarkerCycleCaret(
    after edits: [VimReturnLineEdit],
    originalSelection: NSRange
  ) -> Int {
    guard originalSelection.length == 0, let edit = edits.first else {
      return edits.first?.range.location ?? originalSelection.location
    }
    return edit.range.location + (edit.replacement as NSString).length
  }

  private func vimReturnLineRanges(for selection: NSRange, in text: NSString) -> [NSRange] {
    if selection.length == 0 {
      return [vimReturnLogicalLineRange(containing: selection.location, in: text)]
    }
    let start = min(max(0, selection.location), text.length)
    let end = min(max(start, selection.location + selection.length), text.length)
    let finalProbe = max(start, end - 1)
    var ranges: [NSRange] = []
    var location = vimReturnLogicalLineRange(containing: start, in: text).location
    while location <= finalProbe, location <= text.length {
      let line = vimReturnLogicalLineRange(containing: location, in: text)
      ranges.append(line)
      let next = line.location + line.length
      guard next > location, next <= text.length else { break }
      location = next
    }
    return ranges
  }

  private func vimReturnLogicalLineRange(containing location: Int, in text: NSString) -> NSRange {
    let clamped = min(max(0, location), text.length)
    let isTrailingNewline =
      clamped == text.length && clamped > 0 && text.character(at: clamped - 1) == 0x0A
    if isTrailingNewline { return NSRange(location: clamped, length: 0) }
    let probe = min(clamped, max(0, text.length - 1))
    return text.lineRange(for: NSRange(location: probe, length: 0))
  }

  private func vimReturnLineContent(in line: NSRange, text: NSString) -> VimReturnLine? {
    var end = line.location + line.length
    while end > line.location {
      let ch = text.character(at: end - 1)
      guard ch == 0x0A || ch == 0x0D else { break }
      end -= 1
    }
    guard end >= line.location else { return nil }
    let range = NSRange(location: line.location, length: end - line.location)
    return VimReturnLine(range: range, text: text.substring(with: range))
  }

  private func vimReturnLineAddingBullet(_ line: String) -> String? {
    guard MarkdownOutline.continuationPrefix(in: line) == nil else { return nil }
    let indent = vimReturnLeadingWhitespace(in: line)
    let body = String(line.dropFirst(indent.count))
    return indent + "- " + body
  }

  private func vimReturnLineRemovingBullet(_ line: String) -> String? {
    guard let prefix = MarkdownOutline.continuationPrefix(in: line) else { return nil }
    let indent = vimReturnLeadingWhitespace(in: line)
    let body = String(line.dropFirst(prefix.count))
    return indent + body
  }

  private func vimReturnLeadingWhitespace(in line: String) -> String {
    String(line.prefix { $0 == " " || $0 == "\t" })
  }

  private func vimReturnCaretLocation(
    after edits: [VimReturnLineEdit],
    originalSelection: NSRange,
    removingBullets: Bool
  ) -> Int {
    guard originalSelection.length == 0, let edit = edits.first else {
      return edits.first?.range.location ?? originalSelection.location
    }
    let cursorInLine = originalSelection.location - edit.range.location
    let prefix = MarkdownOutline.continuationPrefix(in: edit.original)
    if removingBullets, let prefix {
      let indentLength = (vimReturnLeadingWhitespace(in: edit.original) as NSString).length
      let prefixLength = (prefix as NSString).length
      if cursorInLine <= indentLength { return originalSelection.location }
      if cursorInLine < prefixLength { return edit.range.location + indentLength }
      return originalSelection.location - (prefixLength - indentLength)
    }
    let indentLength = (vimReturnLeadingWhitespace(in: edit.original) as NSString).length
    return cursorInLine <= indentLength
      ? originalSelection.location : originalSelection.location + 2
  }

  private func exitVisualModeForReturnToggle(engine: VimEngine) {
    if engine.mode != .normal {
      _ = engine.handle(key: "\u{1B}", hasModifiers: false)
    }
    visualAnchor = nil
    visualCaret = nil
    visualLineAnchor = nil
    visualLineCaret = nil
    notifyVimModeChanged()
  }
}

private struct VimReturnLine {
  let range: NSRange
  let text: String
}

private struct VimReturnLineEdit {
  let range: NSRange
  let original: String
  let replacement: String
}
