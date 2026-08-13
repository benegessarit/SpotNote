import AppKit

/// Markdown-style code styling applied as `NSLayoutManager` temporary
/// attributes -- visual only, never touches the Markdown string. Key
/// properties:
///
/// - Backticks stay as literal characters in the document.
/// - Inline `` `code` `` spans get a subtle background + dimmed fences.
/// - Markdown headings get a heavier font in the normal text color; the stored
///   Markdown string stays plain text.
/// - Triple-fenced blocks are NOT background-tinted; instead the inner
///   code is tokenized via `SyntaxHighlighter` and colored per category.
///   Unrecognized languages fall back to a pan-language keyword set.
///
/// Because temporary attributes bypass `NSTextStorage.processEditing`,
/// re-applying color/background spans on every keystroke doesn't invalidate
/// the edited-range layout cache -- which is what used to make the
/// backticks flash. Heading fonts are the exception: AppKit's layout
/// manager only draws non-layout temporary attributes, so headings use
/// storage attributes while still leaving the stored Markdown string
/// unchanged.
enum CodeStyler {
  struct Palette {
    let codeBackground: NSColor
    let codeForeground: NSColor
    let backtickColor: NSColor
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
  }

  /// nvim Visual parity: the selection is a SUBTLE flat lift of the
  /// surface toward the text ink, never the macOS accent blue. David's
  /// live rose-pine resolves Visual to #221F2E over the #191724 base --
  /// exactly a 5% background→text blend (probed via headless nvim
  /// nvim_get_hl, 2026-08-10); light schemes need a stronger step to
  /// stay visible (his own rose-pine config raises Dawn's for the same
  /// reason). Foreground is NOT overridden -- nvim keeps syntax colors
  /// inside the selection.
  @MainActor
  static func applyVisualSelectionColor(to textView: NSTextView, theme: Theme) {
    let base = NSColor(theme.background)
    // Deliberately STRONGER than nvim's probed 5%/9%: on SpotNote's
    // surfaces the nvim-exact blend read as invisible (David 2026-08-11,
    // "still not really visible") -- the RELATIONSHIP (flat surface->text
    // lift, no accent blue, foreground untouched) stays nvim, the depth
    // is his taste.
    let fraction: CGFloat = theme.mode == .dark ? 0.11 : 0.15
    let visualBg = base.blended(withFraction: fraction, of: NSColor(theme.text)) ?? base
    textView.selectedTextAttributes = [.backgroundColor: visualBg]
    // The view paints visual-mode selection (and the yank flash) itself:
    // AppKit swaps in the light unemphasized gray whenever the view is
    // not first responder, which is exactly the band David flagged.
    (textView as? PlaceholderTextView)?.editorVisualSelectionColor = visualBg
    // Search bands: non-current matches sit one step BELOW the Visual
    // band so the current match reads as "the" match.
    let dimFraction: CGFloat = theme.mode == .dark ? 0.07 : 0.10
    (textView as? PlaceholderTextView)?.editorSearchDimBandColor =
      base.blended(withFraction: dimFraction, of: NSColor(theme.text)) ?? base
  }

  @MainActor
  static func apply(to textView: NSTextView, theme: Theme) {
    applyVisualSelectionColor(to: textView, theme: theme)
    guard let layoutManager = textView.layoutManager else { return }
    let nsText = textView.string as NSString
    // Typing hot path: this runs on EVERY text change, and the
    // full-document temporary-attribute clear below invalidates the
    // whole layout each time. All styling here keys on backticks or a
    // pasted URL scheme, so a note without either -- after a pass that
    // left no attributes -- has nothing to clear and nothing to add.
    let hasBackticks = nsText.range(of: "`").location != NSNotFound
    let hasLinks = nsText.range(of: "://").location != NSNotFound
    let placeholderView = textView as? PlaceholderTextView
    if !hasBackticks, !hasLinks, placeholderView?.codeStylerLeftAttributes == false { return }
    placeholderView?.codeStylerLeftAttributes = hasBackticks || hasLinks
    let fullRange = NSRange(location: 0, length: nsText.length)
    clearTransientAttributes(layoutManager, fullRange: fullRange)
    placeholderView?.linkSpans = []
    guard fullRange.length > 0 else { return }
    let palette = palette(for: theme)
    let processed = styleTriples(
      in: nsText,
      fullRange: fullRange,
      layoutManager: layoutManager,
      palette: palette
    )
    styleStorageBackedMarkdown(
      in: nsText,
      fullRange: fullRange,
      textView: textView,
      theme: theme,
      processed: processed
    )
    styleInline(
      in: nsText,
      fullRange: fullRange,
      layoutManager: layoutManager,
      palette: palette,
      processed: processed
    )
    // MUST stay last: conceal rides storage fonts, and the heading pass
    // above re-imposes the base font each restyle (that reset IS the
    // un-conceal path -- see CodeStylerLinks).
    CodeStylerLinks.apply(
      in: nsText,
      textView: textView,
      style: CodeStylerLinks.Style(accent: NSColor(theme.headingText)),
      processed: processed
    )
  }

  @MainActor
  private static func styleStorageBackedMarkdown(
    in nsText: NSString,
    fullRange: NSRange,
    textView: NSTextView,
    theme: Theme,
    processed: [NSRange]
  ) {
    CodeStylerHeading.apply(
      in: nsText,
      fullRange: fullRange,
      textStorage: textView.textStorage,
      style: headingStyle(for: textView, theme: theme),
      processed: processed
    )
    CodeStylerListMarkers.apply(
      in: nsText,
      fullRange: fullRange,
      textStorage: textView.textStorage,
      style: listMarkerStyle(for: textView, theme: theme),
      processed: processed
    )
    CodeStylerSections.apply(
      in: nsText,
      fullRange: fullRange,
      textStorage: textView.textStorage,
      style: sectionStyle(for: theme),
      processed: processed
    )
  }

  // MARK: - Triple fences

  private static func styleTriples(
    in nsText: NSString,
    fullRange: NSRange,
    layoutManager: NSLayoutManager,
    palette: Palette
  ) -> [NSRange] {
    guard let regex = try? NSRegularExpression(pattern: "```([\\s\\S]*?)```") else { return [] }
    var processed: [NSRange] = []
    regex.enumerateMatches(in: nsText as String, range: fullRange) { match, _, _ in
      guard let match else { return }
      let outer = match.range
      let inner = match.range(at: 1)
      dimFences(outer: outer, fenceLength: 3, layoutManager: layoutManager, palette: palette)
      applySyntax(
        innerRange: inner,
        nsText: nsText,
        layoutManager: layoutManager,
        palette: palette
      )
      processed.append(outer)
    }
    return processed
  }

  private static func applySyntax(
    innerRange: NSRange,
    nsText: NSString,
    layoutManager: NSLayoutManager,
    palette: Palette
  ) {
    guard innerRange.length > 0 else { return }
    let body = nsText.substring(with: innerRange)
    let split = SyntaxHighlighter.splitLanguage(from: body)
    let codeStart = innerRange.location + (innerRange.length - (split.code as NSString).length)
    let tokens = SyntaxHighlighter.tokens(in: split.code, language: split.language)
    for token in tokens {
      let absolute = NSRange(location: codeStart + token.range.location, length: token.range.length)
      layoutManager.addTemporaryAttribute(
        .foregroundColor,
        value: color(for: token.category, palette: palette),
        forCharacterRange: absolute
      )
    }
  }

  // MARK: - Inline spans

  private static func styleInline(
    in nsText: NSString,
    fullRange: NSRange,
    layoutManager: NSLayoutManager,
    palette: Palette,
    processed: [NSRange]
  ) {
    guard let regex = try? NSRegularExpression(pattern: "`([^`\\n]+)`") else { return }
    regex.enumerateMatches(in: nsText as String, range: fullRange) { match, _, _ in
      guard let match else { return }
      let outer = match.range
      if processed.contains(where: { NSIntersectionRange($0, outer).length > 0 }) { return }
      let inner = match.range(at: 1)
      layoutManager.addTemporaryAttribute(
        .foregroundColor,
        value: palette.codeForeground,
        forCharacterRange: inner
      )
      layoutManager.addTemporaryAttribute(
        .backgroundColor,
        value: palette.codeBackground,
        forCharacterRange: inner
      )
      dimFences(outer: outer, fenceLength: 1, layoutManager: layoutManager, palette: palette)
    }
  }

  // MARK: - Helpers

  private static func dimFences(
    outer: NSRange,
    fenceLength: Int,
    layoutManager: NSLayoutManager,
    palette: Palette
  ) {
    let left = NSRange(location: outer.location, length: fenceLength)
    let right = NSRange(
      location: outer.location + outer.length - fenceLength,
      length: fenceLength
    )
    layoutManager.addTemporaryAttribute(
      .foregroundColor,
      value: palette.backtickColor,
      forCharacterRange: left
    )
    layoutManager.addTemporaryAttribute(
      .foregroundColor,
      value: palette.backtickColor,
      forCharacterRange: right
    )
  }

  private static func color(for category: SyntaxCategory, palette: Palette) -> NSColor {
    switch category {
    case .keyword: return palette.keyword
    case .string: return palette.string
    case .number: return palette.number
    case .comment: return palette.comment
    }
  }

  @MainActor
  private static func headingStyle(
    for _: NSTextView,
    theme: Theme
  ) -> CodeStylerHeading.Style {
    let bodyForeground = NSColor(theme.text)
    return CodeStylerHeading.Style(
      baseFont: SpotNoteFont.editor(),
      bodyForeground: bodyForeground,
      headingForeground: bodyForeground,
      headingStrokeWidth: -1.15
    )
  }

  @MainActor
  private static func listMarkerStyle(
    for _: NSTextView,
    theme: Theme
  ) -> CodeStylerListMarkers.Style {
    let bodyForeground = NSColor(theme.text)
    return CodeStylerListMarkers.Style(
      baseFont: SpotNoteFont.editor(),
      markerForeground: bodyForeground.withAlphaComponent(theme.mode == .dark ? 0.86 : 0.78),
      doneMarkerForeground: NSColor(theme.headingText)
    )
  }

  private static func sectionStyle(for theme: Theme) -> CodeStylerSections.Style {
    let bodyForeground = NSColor(theme.text)
    return CodeStylerSections.Style(
      trayBodyForeground: bodyForeground.withAlphaComponent(theme.mode == .dark ? 0.82 : 0.76)
    )
  }

  private static func palette(for theme: Theme) -> Palette {
    let base = NSColor(theme.text)
    let accent = NSColor(theme.placeholder)
    if theme.mode == .dark {
      return Palette(
        codeBackground: base.withAlphaComponent(0.08),
        codeForeground: base.withAlphaComponent(0.92),
        backtickColor: accent.withAlphaComponent(0.55),
        keyword: NSColor(red: 0.78, green: 0.52, blue: 0.86, alpha: 1.0),
        string: NSColor(red: 0.82, green: 0.63, blue: 0.56, alpha: 1.0),
        number: NSColor(red: 0.71, green: 0.81, blue: 0.63, alpha: 1.0),
        comment: NSColor(white: 0.55, alpha: 1.0)
      )
    }
    return Palette(
      codeBackground: base.withAlphaComponent(0.06),
      codeForeground: base.withAlphaComponent(0.90),
      backtickColor: accent.withAlphaComponent(0.75),
      keyword: NSColor(red: 0.49, green: 0.11, blue: 0.69, alpha: 1.0),
      string: NSColor(red: 0.64, green: 0.08, blue: 0.08, alpha: 1.0),
      number: NSColor(red: 0.04, green: 0.52, blue: 0.35, alpha: 1.0),
      comment: NSColor(white: 0.45, alpha: 1.0)
    )
  }
}

extension CodeStyler {
  /// Full-document clear of every temporary attribute a styling pass may
  /// have left (code tints, backgrounds, link underlines).
  static func clearTransientAttributes(
    _ layoutManager: NSLayoutManager,
    fullRange: NSRange
  ) {
    layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
    layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
    layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
  }
}
