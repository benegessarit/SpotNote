enum NotePayload {
  static func normalized(_ text: String) -> String? {
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    guard let first = lines.firstIndex(where: { !isBlankLine($0) }),
      let last = lines.lastIndex(where: { !isBlankLine($0) })
    else { return nil }
    return lines[first...last].map(trimTrailingWhitespace).joined(separator: "\n")
  }

  static func trimmingTrailingLineWhitespace(in text: String) -> String {
    text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .map(trimTrailingWhitespace)
      .joined(separator: "\n")
  }

  private static func isBlankLine(_ line: Substring) -> Bool {
    line.allSatisfy { $0 == " " || $0 == "\t" }
  }

  private static func trimTrailingWhitespace(_ line: Substring) -> String {
    var end = line.endIndex
    while end > line.startIndex {
      let previous = line.index(before: end)
      if line[previous] != " " && line[previous] != "\t" { break }
      end = previous
    }
    return String(line[..<end])
  }
}
