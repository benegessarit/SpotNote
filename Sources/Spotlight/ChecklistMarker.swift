import Foundation

/// Markdown file-format marker used only at SpotNote's persistence boundary.
///
/// The live editor stores checklist state separately from the text view string;
/// `[   ]` / `[ x ]` syntax is parsed on load and serialized on save.
enum ChecklistMarker {
  static let unchecked = "[   ]"
  static let checked = "[ x ]"

  struct Match: Equatable {
    let range: NSRange
    let isChecked: Bool
  }

  private static let regex = try? NSRegularExpression(pattern: #"\[\s*(?:x|X)?\s*\]"#)

  static func matches(in text: String) -> [Match] {
    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    return regex?.matches(in: text, range: fullRange).compactMap { result in
      let marker = nsText.substring(with: result.range)
      let compact = marker.filter { !$0.isWhitespace }
      return Match(range: result.range, isChecked: compact == "[x]" || compact == "[X]")
    } ?? []
  }

  static func lineStartMatch(in lineText: String) -> Match? {
    let offset = lineStartInsertionOffset(in: lineText)
    return matches(in: lineText).first { $0.range.location == offset }
  }

  static func lineStartInsertionOffset(in lineText: String) -> Int {
    let nsLine = lineText as NSString
    var offset = 0
    while offset < nsLine.length {
      let ch = nsLine.character(at: offset)
      guard ch == 0x20 || ch == 0x09 else { break }
      offset += 1
    }
    return offset
  }
}
