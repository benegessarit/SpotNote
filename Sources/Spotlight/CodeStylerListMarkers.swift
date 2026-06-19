import AppKit

/// Visual-only Markdown list marker styling.
///
/// SpotNote still stores portable Markdown (`- task`) while drawing the marker
/// with a little more presence, so task bullets read intentional instead of
/// like tiny punctuation.
enum CodeStylerListMarkers {
  struct Style {
    let baseFont: NSFont?
    let markerForeground: NSColor
  }

  static func apply(
    in nsText: NSString,
    fullRange: NSRange,
    textStorage: NSTextStorage?,
    style: Style,
    processed: [NSRange]
  ) {
    guard let textStorage else { return }
    guard let regex = try? NSRegularExpression(pattern: #"(?m)^[ \t]*[-*+](?= )"#) else {
      return
    }
    let markerFont = markerFont(matching: style.baseFont)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: markerFont,
      .foregroundColor: style.markerForeground
    ]

    textStorage.beginEditing()
    defer { textStorage.endEditing() }
    regex.enumerateMatches(in: nsText as String, range: fullRange) { match, _, _ in
      guard let range = match?.range else { return }
      let markerRange = markerCharacterRange(in: range, text: nsText)
      guard !processed.contains(where: { NSIntersectionRange($0, markerRange).length > 0 }) else {
        return
      }
      textStorage.addAttributes(attributes, range: markerRange)
    }
  }

  private static func markerCharacterRange(in range: NSRange, text: NSString) -> NSRange {
    var location = range.location
    let maxLocation = range.location + range.length
    while location < maxLocation {
      let char = text.character(at: location)
      guard char == 0x20 || char == 0x09 else { break }
      location += 1
    }
    return NSRange(location: location, length: 1)
  }

  private static func markerFont(matching font: NSFont?) -> NSFont {
    let base = font ?? .systemFont(ofSize: EditorMetrics.fontSize)
    let sized = base.withSize(base.pointSize + 2)
    let manager = NSFontManager.shared
    let bold = manager.convert(sized, toHaveTrait: .boldFontMask)
    if manager.traits(of: bold).contains(.boldFontMask) {
      return bold
    }
    if base.isFixedPitch {
      return .monospacedSystemFont(ofSize: sized.pointSize, weight: .bold)
    }
    return .boldSystemFont(ofSize: sized.pointSize)
  }
}
