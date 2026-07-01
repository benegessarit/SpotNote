import AppKit

extension PlaceholderTextView {
  /// `,t` -- jump to the in-note `## Tray` section, creating it at the
  /// bottom when absent, and leave the editor in insert mode on a fresh
  /// bullet at the end of that section.
  @discardableResult
  func jumpToTraySectionForVim() -> Bool {
    let target = ensureTrayInsertionLocation()
    revealVimSectionJumpTarget(target)
    return true
  }

  /// `,d` -- jump to the in-note `## Todo` section, creating it before `## Tray`
  /// when absent, and leave the editor in insert mode on a fresh to-do bullet.
  @discardableResult
  func jumpToToDoSectionForVim() -> Bool {
    let target = ensureToDoInsertionLocation()
    revealVimSectionJumpTarget(target)
    return true
  }

  private func revealVimSectionJumpTarget(_ target: Int) {
    let range = NSRange(location: target, length: 0)
    setSelectedRange(range)
    scrollRangeToVisible(range)
    notifyVimModeChanged()
    needsDisplay = true
  }

  private func ensureTrayInsertionLocation() -> Int {
    var nsString = string as NSString
    if headingRange(matching: SpotNoteSectionHeadings.tray, in: nsString) == nil {
      _ = appendMissingTraySection(to: nsString)
      nsString = string as NSString
    }
    guard let heading = headingRange(matching: SpotNoteSectionHeadings.tray, in: nsString) else {
      return nsString.length
    }
    return ensureOpenBulletLineAfter(heading, in: nsString)
  }

  private func ensureToDoInsertionLocation() -> Int {
    var nsString = string as NSString
    if headingRange(matching: SpotNoteSectionHeadings.todo, in: nsString) == nil {
      let insertion = todoSectionInsertionPoint(in: nsString)
      let needsLeadingNewline = insertion > 0 && nsString.character(at: insertion - 1) != 0x0A
      let text = (needsLeadingNewline ? "\n" : "") + SpotNoteSectionHeadings.todo.canonicalLine
      replaceTextForSectionJump(in: NSRange(location: insertion, length: 0), with: text)
      nsString = string as NSString
    }
    guard let heading = headingRange(matching: SpotNoteSectionHeadings.todo, in: nsString) else {
      return nsString.length
    }
    return ensureOpenBulletLineAfter(heading, in: nsString)
  }

  /// TODO inserts before TRAY when present, else at the end of the note.
  private func todoSectionInsertionPoint(in nsString: NSString) -> Int {
    if let tray = headingRange(matching: SpotNoteSectionHeadings.tray, in: nsString) {
      return tray.location
    }
    return nsString.length
  }

  private func appendMissingTraySection(to nsString: NSString) -> Int {
    let prefix: String
    if nsString.length == 0 {
      prefix = SpotNoteSectionHeadings.tray.canonicalLine
    } else if nsString.character(at: nsString.length - 1) == 0x0A {
      prefix = "\n" + SpotNoteSectionHeadings.tray.canonicalLine
    } else {
      prefix = "\n\n" + SpotNoteSectionHeadings.tray.canonicalLine
    }
    let range = NSRange(location: nsString.length, length: 0)
    replaceTextForSectionJump(in: range, with: prefix)
    return nsString.length + (prefix as NSString).length
  }

  /// Appends a fresh `- ` bullet at the END of the section under `heading`
  /// (after its last non-empty line, ignoring internal blank spacer lines),
  /// reusing a trailing blank line when one is already present. Returns the
  /// caret location just past the inserted "- ". Shared by ,d / ,t.
  private func ensureOpenBulletLineAfter(_ heading: NSRange, in nsString: NSString) -> Int {
    var location = heading.location + heading.length
    var insertion = heading.location + heading.length
    while location < nsString.length {
      let line = nsString.lineRange(for: NSRange(location: location, length: 0))
      let content = lineContent(in: line, text: nsString)
      if isMarkdownHeading(content) { break }
      if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        insertion = line.location + line.length
      }
      let next = line.location + line.length
      guard next > location else { break }
      location = next
    }
    return insertBulletLine(at: insertion, in: nsString)
  }

  private func insertBulletLine(at insertion: Int, in nsString: NSString) -> Int {
    if insertion >= nsString.length {
      let replacement =
        nsString.length > 0 && nsString.character(at: nsString.length - 1) != 0x0A
        ? "\n- "
        : "- "
      replaceTextForSectionJump(in: NSRange(location: nsString.length, length: 0), with: replacement)
      return nsString.length + (replacement as NSString).length
    }
    let line = nsString.lineRange(for: NSRange(location: insertion, length: 0))
    let content = lineContent(in: line, text: nsString)
    let isReusableBlankLine =
      !isMarkdownHeading(content) && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if isReusableBlankLine {
      replaceTextForSectionJump(in: lineContentRange(line, in: nsString), with: "- ")
      return line.location + 2
    }
    replaceTextForSectionJump(in: NSRange(location: insertion, length: 0), with: "- \n")
    return insertion + 2
  }

  private func headingRange(
    matching heading: SpotNoteSectionHeadings.Definition,
    in nsString: NSString
  ) -> NSRange? {
    var location = 0
    while location < nsString.length {
      let line = nsString.lineRange(for: NSRange(location: location, length: 0))
      let content = lineContent(in: line, text: nsString)
      if heading.matches(content) {
        return line
      }
      let next = line.location + line.length
      guard next > location else { break }
      location = next
    }
    return nil
  }

  private func lineContent(in line: NSRange, text: NSString) -> String {
    text.substring(with: lineContentRange(line, in: text))
  }

  private func lineContentRange(_ line: NSRange, in text: NSString) -> NSRange {
    NSRange(location: line.location, length: text.lineContentEnd(of: line) - line.location)
  }

  private func isMarkdownHeading(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("#")
  }

  private func replaceTextForSectionJump(in range: NSRange, with replacement: String) {
    guard shouldChangeText(in: range, replacementString: replacement) else { return }
    replaceCharacters(in: range, with: replacement)
    didChangeText()
  }
}
