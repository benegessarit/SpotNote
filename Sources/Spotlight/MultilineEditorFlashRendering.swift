import AppKit

extension PlaceholderTextView {
  func refreshFlashTextAppearance(controller: VimController) {
    guard let prompt = controller.prompt else {
      clearFlashTextAppearance()
      return
    }
    applyFlashTextAppearance(prompt: prompt)
  }

  private func applyFlashTextAppearance(prompt: VimController.Prompt) {
    clearFlashTextAppearance()
    guard case .flash = prompt.kind,
      let layoutManager
    else { return }
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    let fullRange = NSRange(location: 0, length: nsString.length)
    addFlashTemporaryForeground(flashDimmedTextColor, range: fullRange, layoutManager: layoutManager)
    let queryLength = (prompt.buffer as NSString).length
    guard queryLength > 0 else { return }
    let labelsVisible = regularFlashLabelsAreVisible(query: prompt.buffer)
    let visibleHints = visibleRegularFlashTargets()
    for hint in visibleHints {
      let queryRange = NSRange(
        location: hint.location,
        length: min(queryLength, max(0, nsString.length - hint.location))
      )
      if queryRange.length > 0 {
        addFlashTemporaryForeground(flashQueryTextColor, range: queryRange, layoutManager: layoutManager)
      }
      // Labels replace the characters they anchor on (hop/flash
      // `hl_mode = "replace"`): the glyphs the label's ink will COVER go
      // clear and the label letters draw in their place
      // (`drawFlashHints`). The covered span is advance-measured, not
      // one-char -- see `hintHiddenRange`.
      if labelsVisible, let labelRange = flashLabelCharacterRange(for: hint, query: prompt.buffer) {
        let covered = hintHiddenRange(at: labelRange.location, label: hint.label, bold: true)
        addFlashTemporaryForeground(.clear, range: covered, layoutManager: layoutManager)
      }
    }
  }

  /// The characters a hint label visually covers in this PROPORTIONAL
  /// editor. nvim's replace only works on a monospace grid; here a label
  /// wider than its anchor glyph would collide with the next glyph (and
  /// the anchor's advance survives hiding, so a narrower label just
  /// leaves a small gap -- the acceptable direction). Walk forward from
  /// the anchor accumulating glyph advances until the label's ink fits,
  /// minimum one character, never across a line break.
  func hintHiddenRange(at location: Int, label: String, bold: Bool) -> NSRange {
    let nsString = string as NSString
    guard location >= 0, location < nsString.length else {
      return NSRange(location: max(0, location), length: 0)
    }
    let baseFont = font ?? NSFont.systemFont(ofSize: EditorMetrics.fontSize)
    let labelFont =
      bold
      ? NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
      : baseFont
    let labelWidth = (label as NSString).size(withAttributes: [.font: labelFont]).width
    var covered = 0.0
    var length = 0
    while location + length < nsString.length {
      let charRange = nsString.rangeOfComposedCharacterSequence(at: location + length)
      let char = nsString.substring(with: charRange)
      if char == "\n" { break }
      covered += (char as NSString).size(withAttributes: [.font: baseFont]).width
      length = charRange.location + charRange.length - location
      if covered >= labelWidth { break }
    }
    return NSRange(location: location, length: max(1, length))
  }

  func clearFlashTextAppearance() {
    guard let layoutManager else {
      flashTemporaryAttributeRanges = []
      return
    }
    for range in flashTemporaryAttributeRanges where range.length > 0 {
      layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
    }
    flashTemporaryAttributeRanges = []
  }

  private func addFlashTemporaryForeground(
    _ color: NSColor,
    range: NSRange,
    layoutManager: NSLayoutManager
  ) {
    guard range.location >= 0, range.length > 0 else { return }
    layoutManager.addTemporaryAttributes([.foregroundColor: color], forCharacterRange: range)
    flashTemporaryAttributeRanges.append(range)
  }

  private var flashDimmedTextColor: NSColor {
    let base = editorTextAttributes[.foregroundColor] as? NSColor ?? textColor ?? .labelColor
    return base.withAlphaComponent(0.42)
  }

  private var flashQueryTextColor: NSColor {
    NSColor(red: 0.804, green: 0.839, blue: 1.000, alpha: 1.0)
  }

  private var flashLabelTextColor: NSColor {
    NSColor(red: 0.651, green: 0.890, blue: 0.631, alpha: 1.0)
  }

  private var flashActiveLabelTextColor: NSColor {
    NSColor(red: 0.980, green: 0.702, blue: 0.529, alpha: 1.0)
  }

  private func visibleRegularFlashTargets() -> [VimFlashTarget] {
    flashLabelBuffer.isEmpty
      ? flashHints
      : flashHints.filter { $0.label.hasPrefix(flashLabelBuffer) }
  }

  private func flashLabelCharacterRange(for hint: VimFlashTarget, query: String) -> NSRange? {
    let nsString = string as NSString
    guard nsString.length > 0 else { return nil }
    let queryLength = max(0, (query as NSString).length)
    let desiredStart = hint.location + queryLength
    let fallbackStart = min(max(0, hint.location), nsString.length - 1)
    let start = desiredStart < nsString.length ? desiredStart : fallbackStart
    let length = min(max(1, (hint.label as NSString).length), nsString.length - start)
    guard length > 0 else { return nil }
    return NSRange(location: start, length: length)
  }

  func drawFlashHints(in dirtyRect: NSRect) {
    guard !isShowingLineFlashHints || enclosingScrollView?.verticalRulerView == nil else { return }
    guard !flashHints.isEmpty,
      let layoutManager,
      let textContainer
    else { return }
    let query = regularFlashQueryForDrawing()
    if let query, !regularFlashLabelsAreVisible(query: query) { return }
    layoutManager.ensureLayout(for: textContainer)
    for hint in visibleRegularFlashTargets() {
      drawFlashHint(hint, query: query ?? "", dirtyRect: dirtyRect)
    }
  }

  private func regularFlashQueryForDrawing() -> String? {
    guard let prompt = vimController?.prompt,
      case .flash = prompt.kind
    else { return nil }
    return prompt.buffer
  }

  private func drawFlashHint(
    _ hint: VimFlashTarget,
    query: String,
    dirtyRect: NSRect
  ) {
    guard let labelRange = flashLabelCharacterRange(for: hint, query: query),
      let anchor = hintAnchorRects(forCharacterAt: labelRange.location)
    else { return }
    let active = !flashLabelBuffer.isEmpty && hint.label.hasPrefix(flashLabelBuffer)
    drawHintLabel(
      hint.label,
      anchor: anchor,
      ink: active ? flashActiveLabelTextColor : flashLabelTextColor,
      bold: true,
      dirtyRect: dirtyRect
    )
  }

  /// Line fragment + first-glyph rect for the character a hint label
  /// anchors to, in container coordinates. Nil when layout has nothing
  /// there yet.
  func hintAnchorRects(forCharacterAt location: Int) -> (glyph: NSRect, line: NSRect)? {
    guard let layoutManager, let textContainer else { return nil }
    guard location < (string as NSString).length, layoutManager.numberOfGlyphs > 0 else { return nil }
    let glyphIndex = min(
      layoutManager.glyphIndexForCharacter(at: location),
      max(0, layoutManager.numberOfGlyphs - 1)
    )
    let line = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    let glyph = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
    guard !line.isEmpty, !glyph.isEmpty else { return nil }
    return (glyph, line)
  }

  /// Draws a hint label as bare colored letters in the anchor's character
  /// cell, baseline-aligned with its text row — nvim's `hl_mode =
  /// "replace"` look (David's hop/flash render foreground-only letters,
  /// no pill). The glyphs underneath are hidden via a clear temporary
  /// foreground at refresh time, so layout never shifts; the label just
  /// draws where they were.
  func drawHintLabel(
    _ label: String,
    anchor: (glyph: NSRect, line: NSRect),
    ink: NSColor,
    bold: Bool,
    dirtyRect: NSRect
  ) {
    let baseFont = font ?? NSFont.systemFont(ofSize: EditorMetrics.fontSize)
    let labelFont =
      bold
      ? NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
      : baseFont
    let attrs: [NSAttributedString.Key: Any] = [
      .font: labelFont,
      .foregroundColor: ink
    ]
    let labelWidth = ceil((label as NSString).size(withAttributes: attrs).width)
    let fontHeight = ceil(labelFont.ascender - labelFont.descender)
    let baselineY =
      anchor.line.minY
      + LineNumberRuler.synthesizedBaseline(fragmentHeight: anchor.line.height, font: labelFont)
    let rect = NSRect(
      x: textContainerOrigin.x + anchor.glyph.minX,
      y: textContainerOrigin.y + baselineY - labelFont.ascender,
      width: labelWidth,
      height: fontHeight
    )
    guard rect.intersects(dirtyRect) else { return }
    (label as NSString).draw(at: rect.origin, withAttributes: attrs)
  }
}
