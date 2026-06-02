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
      guard regularFlashLabelsAreVisible(query: prompt.buffer),
        let labelRange = flashLabelCharacterRange(for: hint, query: prompt.buffer)
      else { continue }
      addFlashTemporaryForeground(.clear, range: labelRange, layoutManager: layoutManager)
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
      drawFlashHint(
        hint,
        query: query ?? "",
        dirtyRect: dirtyRect,
        layoutManager: layoutManager,
        textContainer: textContainer
      )
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
    dirtyRect: NSRect,
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer
  ) {
    let nsString = string as NSString
    guard let labelRange = flashLabelCharacterRange(for: hint, query: query),
      labelRange.location < nsString.length,
      layoutManager.numberOfGlyphs > 0
    else { return }
    let glyphIndex = min(
      layoutManager.glyphIndexForCharacter(at: labelRange.location),
      max(0, layoutManager.numberOfGlyphs - 1)
    )
    let line = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    let glyph = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
    guard !line.isEmpty, !glyph.isEmpty else { return }
    let rect = flashHintRect(label: hint.label, glyph: glyph, line: line)
    guard rect.intersects(dirtyRect) else { return }
    drawFlashHintLabel(
      label: hint.label,
      in: rect,
      active: !flashLabelBuffer.isEmpty && hint.label.hasPrefix(flashLabelBuffer)
    )
  }

  private func flashHintRect(label: String, glyph: NSRect, line: NSRect) -> NSRect {
    let attrs = flashHintTextAttributes(active: true)
    let labelWidth = ceil((label as NSString).size(withAttributes: attrs).width)
    let height = EditorMetrics.lineHeight
    return NSRect(
      x: textContainerOrigin.x + glyph.minX,
      y: textContainerOrigin.y + line.minY,
      width: max(labelWidth + 2, glyph.width),
      height: height
    )
  }

  private func drawFlashHintLabel(label: String, in rect: NSRect, active: Bool) {
    let attrs = flashHintTextAttributes(active: active)
    let effectiveFont =
      attrs[.font] as? NSFont ?? font
      ?? .monospacedSystemFont(
        ofSize: EditorMetrics.fontSize,
        weight: .bold
      )
    let baseline = LineNumberRuler.synthesizedBaseline(fragmentHeight: rect.height, font: effectiveFont)
    let point = NSPoint(x: rect.minX, y: rect.minY + baseline - effectiveFont.ascender)
    (label as NSString).draw(at: point, withAttributes: attrs)
  }

  private func flashHintTextAttributes(active: Bool) -> [NSAttributedString.Key: Any] {
    let baseFont = font ?? NSFont.monospacedSystemFont(ofSize: EditorMetrics.fontSize, weight: .bold)
    let labelFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
      .withSize(baseFont.pointSize)
    return [
      .font: labelFont,
      .foregroundColor: active ? flashActiveLabelTextColor : flashLabelTextColor
    ]
  }
}
