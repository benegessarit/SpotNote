import Foundation

/// Pure, side-effect-free tidy pass for a SpotNote note, driven by the `\f`
/// motion and the `:fmt` command. It normalizes blank-line spacing *around
/// section headers only* — exactly one blank line above and below each header,
/// and no blank line above the top header — while leaving everything else
/// (bullets, multiline bullet bodies, and blank lines between non-headers)
/// untouched. The transform is idempotent.
enum SpotNoteFormatter {
  /// A header is an ATX heading at the very start of the line: one to six `#`
  /// followed by a space (so a `#label` token, which has no following space, is
  /// not a header). Indented lines are intentionally not treated as headers.
  static func isHeader(_ line: String) -> Bool {
    guard line.first == "#" else { return false }
    var hashes = 0
    for ch in line {
      guard ch == "#" else { break }
      hashes += 1
    }
    guard (1...6).contains(hashes) else { return false }
    let afterHashes = line.index(line.startIndex, offsetBy: hashes)
    return afterHashes < line.endIndex && line[afterHashes] == " "
  }

  private static func isBlank(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).isEmpty
  }

  static func normalize(_ text: String) -> String {
    let hadTrailingNewline = text.hasSuffix("\n")
    let unified =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = unified.components(separatedBy: "\n")
    var out: [String] = []
    var index = 0
    while index < lines.count {
      let line = lines[index]
      guard isHeader(line) else {
        out.append(line)
        index += 1
        continue
      }
      // Collapse any blanks directly above the header, then add exactly one —
      // unless the header is the first content in the note (the top header).
      while let last = out.last, isBlank(last) { out.removeLast() }
      if !out.isEmpty { out.append("") }
      out.append(line)
      // Collapse any blanks directly below the header; add exactly one when the
      // header is followed by more content.
      var next = index + 1
      while next < lines.count, isBlank(lines[next]) { next += 1 }
      if next < lines.count { out.append("") }
      index = next
    }
    var result = out.joined(separator: "\n")
    if hadTrailingNewline && !result.hasSuffix("\n") { result += "\n" }
    return result
  }
}
