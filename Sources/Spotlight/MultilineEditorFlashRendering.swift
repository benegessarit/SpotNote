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
    addFlashTemporaryAttributes(
      [.foregroundColor: flashDimmedTextColor],
      range: fullRange,
      layoutManager: layoutManager
    )
    let queryLength = (prompt.buffer as NSString).length
    guard queryLength > 0 else { return }
    let visibleHints = visibleRegularFlashTargets()
    for hint in visibleHints {
      let queryRange = NSRange(
        location: hint.location,
        length: min(queryLength, max(0, nsString.length - hint.location))
      )
      if queryRange.length > 0 {
        addFlashTemporaryAttributes(
          [.foregroundColor: flashQueryTextColor],
          range: queryRange,
          layoutManager: layoutManager
        )
      }
      guard regularFlashLabelsAreVisible(query: prompt.buffer),
        let labelRange = flashLabelCharacterRange(for: hint, query: prompt.buffer)
      else { continue }
      let active = !flashLabelBuffer.isEmpty && hint.label.hasPrefix(flashLabelBuffer)
      addFlashTemporaryAttributes(
        [
          .foregroundColor: NSColor.clear,
          .backgroundColor: flashLabelFillColor(active: active)
        ],
        range: labelRange,
        layoutManager: layoutManager
      )
    }
  }

  func clearFlashTextAppearance() {
    guard let layoutManager else {
      flashTemporaryAttributeRanges = []
      return
    }
    for range in flashTemporaryAttributeRanges where range.length > 0 {
      layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
      layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
    }
    flashTemporaryAttributeRanges = []
  }

  private func addFlashTemporaryAttributes(
    _ attributes: [NSAttributedString.Key: Any],
    range: NSRange,
    layoutManager: NSLayoutManager
  ) {
    guard range.location >= 0, range.length > 0 else { return }
    layoutManager.addTemporaryAttributes(attributes, forCharacterRange: range)
    flashTemporaryAttributeRanges.append(range)
  }

  private var flashDimmedTextColor: NSColor {
    NSColor(editorTheme.flash.backdropText)
  }

  private var flashQueryTextColor: NSColor {
    NSColor(editorTheme.flash.matchText)
  }

  private func flashLabelTextColor(active: Bool) -> NSColor {
    NSColor(active ? editorTheme.flash.activeLabelText : editorTheme.flash.labelText)
  }

  private func flashLabelFillColor(active: Bool) -> NSColor {
    NSColor(active ? editorTheme.flash.activeLabelFill : editorTheme.flash.labelFill)
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
    let height = EditorMetrics.lineHeight - 2
    return NSRect(
      x: textContainerOrigin.x + glyph.minX - 3,
      y: textContainerOrigin.y + line.minY + 1,
      width: max(labelWidth + 8, glyph.width + 4),
      height: height
    )
  }

  private func drawFlashHintLabel(label: String, in rect: NSRect, active: Bool) {
    let attrs = flashHintTextAttributes(active: active)
    let fill = flashLabelFillColor(active: active)
    let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
    fill.setFill()
    path.fill()
    let effectiveFont =
      attrs[.font] as? NSFont ?? font
      ?? .monospacedSystemFont(
        ofSize: EditorMetrics.fontSize,
        weight: .bold
      )
    let labelSize = (label as NSString).size(withAttributes: attrs)
    let baseline = LineNumberRuler.synthesizedBaseline(fragmentHeight: rect.height, font: effectiveFont)
    let point = NSPoint(
      x: rect.midX - labelSize.width / 2,
      y: rect.minY + baseline - effectiveFont.ascender
    )
    (label as NSString).draw(at: point, withAttributes: attrs)
  }

  private func flashHintTextAttributes(active: Bool) -> [NSAttributedString.Key: Any] {
    let baseFont = font ?? NSFont.monospacedSystemFont(ofSize: EditorMetrics.fontSize, weight: .bold)
    let labelFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
      .withSize(baseFont.pointSize)
    return [
      .font: labelFont,
      .foregroundColor: flashLabelTextColor(active: active)
    ]
  }
}
