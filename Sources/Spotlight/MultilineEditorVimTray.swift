import AppKit

extension PlaceholderTextView {
  /// `gT` -- jump to the in-note `## Tray` section, creating it at the
  /// bottom when absent, and leave the editor in insert mode on the next
  /// open line in that section.
  @discardableResult
  func jumpToTraySectionForVim() -> Bool {
    let target = ensureTrayInsertionLocation()
    revealVimSectionJumpTarget(target)
    return true
  }

  /// `gD` -- jump to the in-note `## To Do` section, creating it at the
  /// top when absent, and leave the editor in insert mode on a fresh task
  /// bullet before any later section such as `## Tray`.
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
    guard let heading = headingRange(named: "## Tray", in: nsString) else {
      return appendMissingTraySection(to: nsString)
    }
    return ensureOpenLineAfterTrayHeading(heading, in: nsString)
  }

  private func ensureToDoInsertionLocation() -> Int {
    var nsString = string as NSString
    if headingRange(named: "## To Do", in: nsString) == nil {
      replaceTextForSectionJump(in: NSRange(location: 0, length: 0), with: "## To Do\n")
      nsString = string as NSString
    }
    guard let heading = headingRange(named: "## To Do", in: nsString) else {
      return nsString.length
    }
    return ensureOpenBulletLineAfterToDoHeading(heading, in: nsString)
  }

  private func appendMissingTraySection(to nsString: NSString) -> Int {
    let prefix: String
    if nsString.length == 0 {
      prefix = "## Tray\n"
    } else if nsString.character(at: nsString.length - 1) == 0x0A {
      prefix = "\n## Tray\n"
    } else {
      prefix = "\n\n## Tray\n"
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

  private func ensureOpenBulletLineAfterToDoHeading(_ heading: NSRange, in nsString: NSString) -> Int {
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

  private func headingRange(named headingName: String, in nsString: NSString) -> NSRange? {
    var location = 0
    while location < nsString.length {
      let line = nsString.lineRange(for: NSRange(location: location, length: 0))
      let content = lineContent(in: line, text: nsString)
      let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.localizedCaseInsensitiveCompare(headingName) == .orderedSame {
        return line
      }
      let next = line.location + line.length
      guard next > location else { break }
      location = next
    }
    return nil
  }

  private func lineContent(in line: NSRange, text: NSString) -> String {
    var end = line.location + line.length
    while end > line.location {
      let ch = text.character(at: end - 1)
      guard ch == 0x0A || ch == 0x0D else { break }
      end -= 1
    }
    return text.substring(with: NSRange(location: line.location, length: end - line.location))
  }

  private func lineContentRange(_ line: NSRange, in text: NSString) -> NSRange {
    var end = line.location + line.length
    while end > line.location {
      let ch = text.character(at: end - 1)
      guard ch == 0x0A || ch == 0x0D else { break }
      end -= 1
    }
    return NSRange(location: line.location, length: end - line.location)
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
