import Foundation

enum ChecklistLineState: Equatable, Sendable {
  case unchecked
  case checked

  var markdownMarker: String {
    switch self {
    case .unchecked: ChecklistMarker.unchecked
    case .checked: ChecklistMarker.checked
    }
  }
}

struct ChecklistDocument: Equatable, Sendable {
  var text: String
  var checklistLines: [Int: ChecklistLineState]

  static func parseMarkdown(_ markdown: String) -> ChecklistDocument {
    var visibleLines: [String] = []
    var states: [Int: ChecklistLineState] = [:]
    let lines = markdown.components(separatedBy: "\n")
    visibleLines.reserveCapacity(lines.count)

    for (index, line) in lines.enumerated() {
      let parsed = parseLine(line)
      visibleLines.append(parsed.visible)
      if let state = parsed.state {
        states[index] = state
      }
    }

    return ChecklistDocument(text: visibleLines.joined(separator: "\n"), checklistLines: states)
  }

  static func serializeMarkdown(text: String, checklistLines: [Int: ChecklistLineState]) -> String {
    var lines = text.components(separatedBy: "\n")
    for (index, state) in checklistLines where index >= 0 && index < lines.count {
      lines[index] = insertingMarkdownMarker(state.markdownMarker, into: lines[index])
    }
    return lines.joined(separator: "\n")
  }

  static func prunedChecklistLines(
    _ checklistLines: [Int: ChecklistLineState],
    for text: String
  ) -> [Int: ChecklistLineState] {
    let lineCount = max(1, text.components(separatedBy: "\n").count)
    return checklistLines.filter { index, _ in index >= 0 && index < lineCount }
  }

  private static func parseLine(_ line: String) -> (visible: String, state: ChecklistLineState?) {
    guard let match = ChecklistMarker.lineStartMatch(in: line) else { return (line, nil) }
    let nsLine = line as NSString
    let removeRange = markdownMarkerStorageRange(for: match, in: nsLine)
    let visible = nsLine.replacingCharacters(in: removeRange, with: "")
    return (visible, match.isChecked ? .checked : .unchecked)
  }

  private static func markdownMarkerStorageRange(
    for match: ChecklistMarker.Match,
    in line: NSString
  ) -> NSRange {
    var length = match.range.length
    let after = match.range.location + match.range.length
    if after < line.length, line.substring(with: NSRange(location: after, length: 1)) == " " {
      length += 1
    }
    return NSRange(location: match.range.location, length: length)
  }

  private static func insertingMarkdownMarker(_ marker: String, into line: String) -> String {
    let offset = ChecklistMarker.lineStartInsertionOffset(in: line)
    let nsLine = line as NSString
    return nsLine.replacingCharacters(
      in: NSRange(location: offset, length: 0),
      with: marker + " "
    )
  }
}
