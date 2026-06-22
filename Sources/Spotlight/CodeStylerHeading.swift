import AppKit

enum CodeStylerHeading {
  struct Style {
    let baseFont: NSFont?
    let bodyForeground: NSColor
    let headingForeground: NSColor
  }

  static func apply(
    in nsText: NSString,
    fullRange: NSRange,
    textStorage: NSTextStorage?,
    style: Style,
    processed: [NSRange]
  ) {
    guard let textStorage else { return }
    guard let regex = try? NSRegularExpression(pattern: "(?m)^[ \\t]{0,3}#{1,6}(?:[ \\t]+[^\\n]*)?$") else {
      return
    }
    let baseFont = bodyFont(matching: style.baseFont)
    let headingFont = boldFont(matching: baseFont)
    var headingRanges: [NSRange] = []
    regex.enumerateMatches(in: nsText as String, range: fullRange) { match, _, _ in
      guard let range = match?.range else { return }
      guard !processed.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { return }
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
    NSRange(location: lineRange.location, length: nsText.lineContentEnd(of: lineRange) - lineRange.location)
  }

  private static func applyTextAttributes(
    font: NSFont,
    foreground: NSColor,
    to range: NSRange,
    in storage: NSTextStorage
  ) {
    var fontRange = NSRange(location: NSNotFound, length: 0)
    var colorRange = NSRange(location: NSNotFound, length: 0)
    let current = storage.attribute(.font, at: range.location, effectiveRange: &fontRange) as? NSFont
    let currentColor =
      storage.attribute(
        .foregroundColor,
        at: range.location,
        effectiveRange: &colorRange
      ) as? NSColor
    let fontAlreadyCoversRange = current == font && contains(fontRange, range)
    let colorAlreadyCoversRange = colorsMatch(currentColor, foreground) && contains(colorRange, range)
    guard !fontAlreadyCoversRange || !colorAlreadyCoversRange else { return }
    storage.addAttributes([.font: font, .foregroundColor: foreground], range: range)
  }

  private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
    guard outer.location != NSNotFound else { return false }
    return inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
  }

  private static func bodyFont(matching font: NSFont?) -> NSFont {
    let base = font ?? .systemFont(ofSize: EditorMetrics.fontSize)
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
    let base = font ?? .systemFont(ofSize: EditorMetrics.fontSize)
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
