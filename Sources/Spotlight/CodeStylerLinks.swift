import AppKit

/// Display-only URL concealment + tinting -- nvim conceallevel parity for
/// pasted links. Layout-affecting conceal rides STORAGE attributes exactly
/// like `CodeStylerHeading` fonts (the stored Markdown string never
/// changes); accent tint and dotted underline ride temporary attributes
/// like every other inline span.
///
/// Ordering contract: MUST run after `CodeStylerHeading.apply`. The
/// heading pass re-imposes the base font on every line each restyle, so a
/// span this pass declines to shrink (caret inside the link, or the link
/// left the document) returns to full size for free -- that ordering IS
/// the un-conceal path.
enum CodeStylerLinks {
  struct Style {
    let accent: NSColor
  }

  /// Font that collapses concealed spans to a hairline: 0.1pt keeps every
  /// glyph advance sub-pixel without the invalid zero-size font. The host
  /// span keeps the base font, so it alone holds the line height.
  @MainActor static let concealFont = NSFont.systemFont(ofSize: 0.1)

  @MainActor
  static func apply(
    in nsText: NSString,
    textView: NSTextView,
    style: Style,
    processed: [NSRange]
  ) {
    let spans = LinkDetection.spans(in: nsText as String).filter { span in
      !processed.contains { NSIntersectionRange($0, span.range).length > 0 }
    }
    (textView as? PlaceholderTextView)?.linkSpans = spans
    guard !spans.isEmpty, let layoutManager = textView.layoutManager,
      let storage = textView.textStorage
    else { return }
    let selection = textView.selectedRange
    // Storage conceal and temporary-attribute tint stay in SEPARATE
    // phases: a temporary attribute inside beginEditing/endEditing makes
    // display invalidation generate glyphs mid-edit, which raises (and
    // crashed the app at launch on a window-hosted first style).
    storage.beginEditing()
    for span in spans where !touches(selection, span.range) {
      conceal(span.leadingConceal, in: storage)
      conceal(span.trailingConceal, in: storage)
    }
    storage.endEditing()
    for span in spans {
      let revealed = touches(selection, span.range)
      tint(span, revealed: revealed, style: style, layoutManager: layoutManager)
    }
  }

  /// Selection-adjacency used for reveal: a zero-length caret touching
  /// either end counts, so arrowing up against a link opens it before the
  /// caret crosses into the concealed prefix.
  static func touches(_ selection: NSRange, _ range: NSRange) -> Bool {
    if selection.length == 0 {
      return selection.location >= range.location && selection.location <= NSMaxRange(range)
    }
    return NSIntersectionRange(selection, range).length > 0
  }

  @MainActor
  private static func conceal(_ range: NSRange, in storage: NSTextStorage) {
    guard range.length > 0 else { return }
    storage.addAttribute(.font, value: concealFont, range: range)
  }

  @MainActor
  private static func tint(
    _ span: LinkSpan,
    revealed: Bool,
    style: Style,
    layoutManager: NSLayoutManager
  ) {
    let tintRange = revealed ? span.range : span.visibleRange
    layoutManager.addTemporaryAttribute(
      .foregroundColor,
      value: style.accent,
      forCharacterRange: tintRange
    )
    layoutManager.addTemporaryAttributes(
      [
        .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
        .underlineColor: style.accent.withAlphaComponent(0.65)
      ],
      forCharacterRange: tintRange
    )
  }
}
