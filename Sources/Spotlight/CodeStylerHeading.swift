import AppKit

enum CodeStylerHeading {
  struct Style {
    let baseFont: NSFont?
    let bodyForeground: NSColor
    let headingForeground: NSColor
    let headingStrokeWidth: CGFloat
  }

  static func apply(
    in nsText: NSString,
    fullRange: NSRange,
    textStorage: NSTextStorage?,
    style: Style,
    processed: [NSRange]
  ) {
    guard let textStorage else { return }
    guard
      let regex = try? NSRegularExpression(pattern: "(?m)^[ \\t]{0,3}#{1,6}(?:[ \\t]+[^\\n]*)?$")
    else {
      return
    }
    let baseFont = bodyFont(matching: style.baseFont)
    let headingFont = boldFont(matching: baseFont)
    var headingRanges: [NSRange] = []
    regex.enumerateMatches(in: nsText as String, range: fullRange) { match, _, _ in
      guard let range = match?.range else { return }
      guard !processed.contains(where: { NSIntersectionRange($0, range).length > 0 }) else {
        return
      }
      headingRanges.append(range)
    }

    textStorage.beginEditing()
    defer { textStorage.endEditing() }
    var location = 0
    while location < fullRange.length {
      let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
      let contentRange = lineContentRange(for: lineRange, in: nsText)
      if contentRange.length > 0 {
        let isHeading = headingRanges.contains { NSEqualRanges($0, contentRange) }
        applyTextAttributes(
          font: isHeading ? headingFont : baseFont,
          foreground: isHeading ? style.headingForeground : style.bodyForeground,
          strokeWidth: isHeading ? style.headingStrokeWidth : nil,
          to: contentRange,
          in: textStorage
        )
      }
      let next = lineRange.location + lineRange.length
      guard next > location else { break }
      location = next
    }
  }

  private static func lineContentRange(for lineRange: NSRange, in nsText: NSString) -> NSRange {
    NSRange(
      location: lineRange.location,
      length: nsText.lineContentEnd(of: lineRange) - lineRange.location
    )
  }

  private static func applyTextAttributes(
    font: NSFont,
    foreground: NSColor,
    strokeWidth: CGFloat?,
    to range: NSRange,
    in storage: NSTextStorage
  ) {
    var fontRange = NSRange(location: NSNotFound, length: 0)
    var colorRange = NSRange(location: NSNotFound, length: 0)
    let current =
      storage.attribute(.font, at: range.location, effectiveRange: &fontRange) as? NSFont
    let currentColor =
      storage.attribute(
        .foregroundColor,
        at: range.location,
        effectiveRange: &colorRange
      ) as? NSColor
    let fontAlreadyCoversRange = current == font && contains(fontRange, range)
    let colorAlreadyCoversRange =
      colorsMatch(currentColor, foreground) && contains(colorRange, range)
    let strokeAlreadyMatches = strokeMatches(strokeWidth, in: range, storage: storage)
    guard !fontAlreadyCoversRange || !colorAlreadyCoversRange || !strokeAlreadyMatches else {
      return
    }
    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
    if let strokeWidth {
      attributes[.strokeWidth] = strokeWidth
    }
    storage.addAttributes(attributes, range: range)
    if strokeWidth == nil {
      storage.removeAttribute(.strokeWidth, range: range)
    }
  }

  private static func strokeMatches(
    _ strokeWidth: CGFloat?,
    in range: NSRange,
    storage: NSTextStorage
  ) -> Bool {
    guard let strokeWidth else {
      return !hasStrokeWidth(in: range, storage: storage)
    }
    var strokeRange = NSRange(location: NSNotFound, length: 0)
    let current =
      storage.attribute(.strokeWidth, at: range.location, effectiveRange: &strokeRange) as? NSNumber
    guard contains(strokeRange, range), let current else { return false }
    return abs(CGFloat(current.doubleValue) - strokeWidth) < 0.001
  }

  private static func hasStrokeWidth(in range: NSRange, storage: NSTextStorage) -> Bool {
    var found = false
    storage.enumerateAttribute(.strokeWidth, in: range) { value, _, stop in
      if value != nil {
        found = true
        stop.pointee = true
      }
    }
    return found
  }

  private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
    guard outer.location != NSNotFound else { return false }
    return inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
  }

  private static func bodyFont(matching font: NSFont?) -> NSFont {
    let base = font ?? SpotNoteFont.editor()
    let manager = NSFontManager.shared
    let converted = manager.convert(base, toNotHaveTrait: .boldFontMask)
    if !manager.traits(of: converted).contains(.boldFontMask) {
      return converted
    }
    if base.isFixedPitch {
      return .monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
    }
    return .systemFont(ofSize: base.pointSize, weight: .regular)
  }

  private static func boldFont(matching font: NSFont?) -> NSFont {
    let base = font ?? SpotNoteFont.editor()
    let manager = NSFontManager.shared
    let converted = manager.convert(base, toHaveTrait: .boldFontMask)
    if manager.traits(of: converted).contains(.boldFontMask) {
      return converted
    }
    if base.isFixedPitch {
      return .monospacedSystemFont(ofSize: base.pointSize, weight: .bold)
    }
    return .boldSystemFont(ofSize: base.pointSize)
  }

  private static func colorsMatch(_ lhs: NSColor?, _ rhs: NSColor) -> Bool {
    guard let left = lhs?.usingColorSpace(.sRGB), let right = rhs.usingColorSpace(.sRGB) else {
      return lhs?.isEqual(rhs) == true
    }
    return abs(left.redComponent - right.redComponent) < 0.001
      && abs(left.greenComponent - right.greenComponent) < 0.001
      && abs(left.blueComponent - right.blueComponent) < 0.001
      && abs(left.alphaComponent - right.alphaComponent) < 0.001
  }
}
