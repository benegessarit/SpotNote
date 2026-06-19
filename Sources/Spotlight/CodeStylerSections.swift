import AppKit

enum CodeStylerSections {
  struct Style {
    let trayBodyForeground: NSColor
  }

  static func apply(
    in nsText: NSString,
    fullRange: NSRange,
    textStorage: NSTextStorage?,
    style: Style,
    processed: [NSRange]
  ) {
    guard let textStorage else { return }
    guard fullRange.length > 0 else { return }
    var isInsideTray = false
    var location = fullRange.location
    let end = fullRange.location + fullRange.length

    textStorage.beginEditing()
    defer { textStorage.endEditing() }

    while location < end {
      let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
      let contentRange = lineContentRange(for: lineRange, in: nsText)
      if contentRange.length > 0, !intersectsProcessed(contentRange, processed: processed) {
        let content = nsText.substring(with: contentRange)
        if isMarkdownHeading(content) {
          isInsideTray = SpotNoteSectionHeadings.tray.matches(content)
        } else if isInsideTray {
          textStorage.addAttribute(
            .foregroundColor,
            value: style.trayBodyForeground,
            range: contentRange
          )
        }
      }

      let next = lineRange.location + lineRange.length
      guard next > location else { break }
      location = next
    }
  }

  private static func lineContentRange(for lineRange: NSRange, in nsText: NSString) -> NSRange {
    var end = lineRange.location + lineRange.length
    while end > lineRange.location {
      let ch = nsText.character(at: end - 1)
      guard ch == 0x0A || ch == 0x0D else { break }
      end -= 1
    }
    return NSRange(location: lineRange.location, length: max(0, end - lineRange.location))
  }

  private static func isMarkdownHeading(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("#")
  }

  private static func intersectsProcessed(_ range: NSRange, processed: [NSRange]) -> Bool {
    processed.contains { NSIntersectionRange($0, range).length > 0 }
  }
}
