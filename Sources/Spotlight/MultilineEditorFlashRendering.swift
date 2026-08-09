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
    let visibleHints = visibleRegularFlashTargets()
    for hint in visibleHints {
      let queryRange = NSRange(
        location: hint.location,
        length: min(queryLength, max(0, nsString.length - hint.location))
      )
      if queryRange.length > 0 {
        addFlashTemporaryForeground(flashQueryTextColor, range: queryRange, layoutManager: layoutManager)
      }
    }
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
    drawHintChip(
      hint.label,
      glyph: anchor.glyph,
      line: anchor.line,
      fill: active ? flashActiveLabelTextColor : flashLabelTextColor,
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

  /// Ink for hint-label chips: rose-pine base, the dark ground the
  /// hop/flash palette was designed against in David's nvim.
  static let hintChipInk = NSColor(red: 0x19 / 255, green: 0x17 / 255, blue: 0x24 / 255, alpha: 1)

  /// Draws a hint label as an opaque rounded chip over `glyph`,
  /// baseline-aligned with its text row. hop's `hl_mode = "replace"`
  /// (swap the character cell for the label) only aligns on a monospace
  /// grid; in this proportional editor a label's advance never matches
  /// the hidden glyph's, so the chip covers the glyph and the
  /// surrounding text keeps its layout.
  func drawHintChip(_ label: String, glyph: NSRect, line: NSRect, fill: NSColor, dirtyRect: NSRect) {
    let chipFont = font ?? NSFont.systemFont(ofSize: EditorMetrics.fontSize)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: chipFont,
      .foregroundColor: Self.hintChipInk
    ]
    let labelWidth = ceil((label as NSString).size(withAttributes: attrs).width)
    let fontHeight = ceil(chipFont.ascender - chipFont.descender)
    let baselineY = line.minY + LineNumberRuler.synthesizedBaseline(fragmentHeight: line.height, font: chipFont)
    let rect = NSRect(
      x: textContainerOrigin.x + glyph.minX - 1,
      y: textContainerOrigin.y + baselineY - chipFont.ascender - 1,
      width: max(labelWidth + 6, glyph.width + 2),
      height: fontHeight + 2
    )
    guard rect.intersects(dirtyRect) else { return }
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
    let point = NSPoint(
      x: rect.minX + (rect.width - labelWidth) / 2,
      y: textContainerOrigin.y + baselineY - chipFont.ascender
    )
    (label as NSString).draw(at: point, withAttributes: attrs)
  }
}
