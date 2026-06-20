import AppKit

extension PlaceholderTextView {
  /// `gT` -- jump to the in-note `## TRAY` section, creating it at the
  /// bottom when absent, and leave the editor in insert mode on the next
  /// open line in that section.
  @discardableResult
  func jumpToTraySectionForVim() -> Bool {
    let target = ensureTrayInsertionLocation()
    revealVimSectionJumpTarget(target)
    return true
  }

  /// `gH` -- jump to the in-note `## HABITS` section, creating it at the
  /// top when absent, and leave the editor in insert mode on a fresh habit
  /// bullet before any later section such as `## TRAY`.
  @discardableResult
  func jumpToHabitsSectionForVim() -> Bool {
    let target = ensureHabitsInsertionLocation()
    revealVimSectionJumpTarget(target)
    return true
  }

  /// `gD` -- jump to the in-note `## TODO` section, creating it (between
  /// `## HABITS` and `## TRAY`) when absent, and leave the editor in insert
  /// mode on a fresh to-do bullet.
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
    let nsString = string as NSString
    guard let heading = headingRange(matching: SpotNoteSectionHeadings.tray, in: nsString) else {
      return appendMissingTraySection(to: nsString)
    }
    return ensureOpenLineAfterTrayHeading(heading, in: nsString)
  }

  private func ensureHabitsInsertionLocation() -> Int {
    var nsString = string as NSString
    if headingRange(matching: SpotNoteSectionHeadings.habits, in: nsString) == nil {
      replaceTextForSectionJump(
        in: NSRange(location: 0, length: 0),
        with: SpotNoteSectionHeadings.habits.canonicalLine
      )
      nsString = string as NSString
    }
    guard let heading = headingRange(matching: SpotNoteSectionHeadings.habits, in: nsString) else {
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

  /// TODO sits between HABITS and TRAY: insert before TRAY when present, else at
  /// the end of the note.
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

  private func ensureOpenLineAfterTrayHeading(_ heading: NSRange, in nsString: NSString) -> Int {
    let scan = scanSectionAfterHeading(heading, in: nsString)
    if let target = existingTrayOpenLine(from: scan, in: nsString) { return target }
    return insertOpenTrayLine(at: scan.sectionEnd, in: nsString)
  }

  private func scanSectionAfterHeading(_ heading: NSRange, in nsString: NSString) -> SectionScan {
    var location = heading.location + heading.length
    var scan = SectionScan(sectionEnd: nsString.length)

    while location < nsString.length {
      let line = nsString.lineRange(for: NSRange(location: location, length: 0))
      let content = lineContent(in: line, text: nsString)
      if isMarkdownHeading(content) { return scan.ending(at: line.location) }
      scan.record(line: line, content: content)

      let next = line.location + line.length
      guard next > location else { break }
      location = next
    }
    return scan
  }

  private func existingTrayOpenLine(from scan: SectionScan, in nsString: NSString) -> Int? {
    if let lastContentLineEnd = scan.lastContentLineEnd {
      if lastContentLineEnd < scan.sectionEnd { return lastContentLineEnd }
      return scan.sectionEnd >= nsString.length && endsWithNewline(nsString) ? nsString.length : nil
    }
    if let firstBlankLine = scan.firstBlankLine { return firstBlankLine }
    return scan.sectionEnd >= nsString.length && endsWithNewline(nsString) ? nsString.length : nil
  }

  private func insertOpenTrayLine(at insertion: Int, in nsString: NSString) -> Int {
    let insertsAtEnd = insertion >= nsString.length
    replaceTextForSectionJump(in: NSRange(location: insertion, length: 0), with: "\n")
    return insertsAtEnd ? insertion + 1 : insertion
  }

  private func endsWithNewline(_ nsString: NSString) -> Bool {
    guard nsString.length > 0 else { return false }
    let character = nsString.character(at: nsString.length - 1)
    return character == 0x0A || character == 0x0D
  }

  private func ensureOpenBulletLineAfter(_ heading: NSRange, in nsString: NSString) -> Int {
    var location = heading.location + heading.length
    while location < nsString.length {
      let line = nsString.lineRange(for: NSRange(location: location, length: 0))
      let content = lineContent(in: line, text: nsString)
      if isMarkdownHeading(content) { break }
      if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        replaceTextForSectionJump(in: lineContentRange(line, in: nsString), with: "- ")
        return line.location + 2
      }
      let next = line.location + line.length
      guard next > location else { break }
      location = next
    }

    if location >= nsString.length {
      let insertion = nsString.length
      let replacement =
        nsString.length > 0 && nsString.character(at: nsString.length - 1) != 0x0A
        ? "\n- "
        : "- "
      replaceTextForSectionJump(in: NSRange(location: insertion, length: 0), with: replacement)
      return insertion + (replacement as NSString).length
    }

    replaceTextForSectionJump(in: NSRange(location: location, length: 0), with: "- \n")
    return location + 2
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

  private struct SectionScan {
    var firstBlankLine: Int?
    var lastContentLineEnd: Int?
    var sectionEnd: Int

    mutating func record(line: NSRange, content: String) {
      if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if lastContentLineEnd == nil, firstBlankLine == nil { firstBlankLine = line.location }
      } else {
        lastContentLineEnd = line.location + line.length
      }
    }

    func ending(at location: Int) -> SectionScan {
      SectionScan(firstBlankLine: firstBlankLine, lastContentLineEnd: lastContentLineEnd, sectionEnd: location)
    }
  }
}
