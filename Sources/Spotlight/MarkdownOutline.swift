import Foundation

/// Tiny Markdown-list helper for SpotNote's capture editor.
///
/// This intentionally stays narrow: it recognizes list prefixes that make sense
/// in a scratch/task inbox and leaves non-list prose alone.
enum MarkdownOutline {
  static let indentUnit = "  "

  static func standaloneMarkerCycleReplacement(for line: String) -> String? {
    let indent = leadingWhitespace(in: line)
    let body = line.dropFirst(indent.count)
    let marker = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if marker == "-" { return indent + "x" }
    if marker == "x" { return "" }
    return nil
  }

  static func continuationPrefix(in line: String) -> String? {
    let scalars = Array(line.unicodeScalars)
    var index = 0
    while index < scalars.count, scalars[index] == " " || scalars[index] == "\t" {
      index += 1
    }
    guard index < scalars.count else { return nil }

    if ["-", "*", "+"].contains(String(scalars[index])) {
      let afterMarker = index + 1
      guard afterMarker < scalars.count, scalars[afterMarker] == " " else { return nil }
      return String(String.UnicodeScalarView(scalars[0...afterMarker]))
    }

    var digitEnd = index
    while digitEnd < scalars.count, CharacterSet.decimalDigits.contains(scalars[digitEnd]) {
      digitEnd += 1
    }
    let isOrderedList =
      digitEnd > index
      && digitEnd + 1 < scalars.count
      && scalars[digitEnd] == "."
      && scalars[digitEnd + 1] == " "
    if isOrderedList {
      return String(String.UnicodeScalarView(scalars[0...(digitEnd + 1)]))
    }

    return nil
  }

  static func isListLine(_ line: String) -> Bool {
    continuationPrefix(in: line) != nil
  }

  static func isBareListItem(_ line: String) -> Bool {
    guard let prefix = continuationPrefix(in: line) else { return false }
    let body = line.dropFirst(prefix.count)
    return body.allSatisfy { $0 == " " || $0 == "\t" }
  }

  static func indentedLine(_ line: String) -> String? {
    guard isListLine(line) else { return nil }
    return indentUnit + line
  }

  static func outdentedLine(_ line: String) -> String? {
    guard isListLine(line) else { return nil }
    var removal = 0
    for ch in line.prefix(indentUnit.count) where ch == " " {
      removal += 1
    }
    guard removal > 0 else { return nil }
    return String(line.dropFirst(removal))
  }

  private static func leadingWhitespace(in line: String) -> String {
    String(line.prefix { $0 == " " || $0 == "\t" })
  }
}
