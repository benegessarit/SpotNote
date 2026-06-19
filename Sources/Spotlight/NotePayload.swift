enum NotePayload {
  static func normalized(_ text: String) -> String? {
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    guard let first = lines.firstIndex(where: { !isBlankLine($0) }),
      let last = lines.lastIndex(where: { !isBlankLine($0) })
    else { return nil }
    return lines[first...last].joined(separator: "\n")
  }

  private static func isBlankLine(_ line: Substring) -> Bool {
    line.allSatisfy { $0 == " " || $0 == "\t" }
  }
}
