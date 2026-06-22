import AppKit

private struct LineFlashDrawStyle {
  let font: NSFont
  let defaultAttrs: [NSAttributedString.Key: Any]
  let activeAttrs: [NSAttributedString.Key: Any]
  let buffer: String
}

extension LineNumberRuler {
  func drawLineFlashHints(
    in ctx: DrawContext,
    textView: PlaceholderTextView,
    text: NSString
  ) {
    let visibleHints =
      textView.flashLabelBuffer.isEmpty
      ? textView.flashHints
      : textView.flashHints.filter { $0.label.hasPrefix(textView.flashLabelBuffer) }
    let labelsByLocation = Dictionary(uniqueKeysWithValues: visibleHints.map { ($0.location, $0.label) })
    guard !labelsByLocation.isEmpty else { return }
    let style = lineFlashDrawStyle(buffer: textView.flashLabelBuffer)
    let lm = ctx.layoutManager
    let all = NSRange(location: 0, length: lm.numberOfGlyphs)
    lm.enumerateLineFragments(forGlyphRange: all) { frag, _, _, glyphs, stop in
      if frag.origin.y >= ctx.visibleRect.maxY {
        stop.pointee = true
        return
      }
      guard frag.maxY > ctx.visibleRect.minY else { return }
      let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
      guard let label = labelsByLocation[chars.location] else { return }
      let offset = lm.location(forGlyphAt: glyphs.location).y
      let baselineY = frag.origin.y + offset + ctx.insetY + ctx.textViewOriginInRuler.y
      self.drawFlashLabel(label, baselineY: baselineY, style: style)
    }
    drawExtraLineFragmentFlashLabel(labelsByLocation: labelsByLocation, ctx: ctx, text: text, style: style)
  }

  private func drawExtraLineFragmentFlashLabel(
    labelsByLocation: [Int: String],
    ctx: DrawContext,
    text: NSString,
    style: LineFlashDrawStyle
  ) {
    guard let label = labelsByLocation[text.length], text.hasSuffix("\n") else { return }
    let extra = ctx.layoutManager.extraLineFragmentRect
    guard !extra.isEmpty,
      extra.maxY > ctx.visibleRect.minY,
      extra.origin.y < ctx.visibleRect.maxY
    else { return }
    let offset = Self.synthesizedBaseline(fragmentHeight: extra.height, font: editorFont)
    let baselineY = extra.origin.y + offset + ctx.insetY + ctx.textViewOriginInRuler.y
    drawFlashLabel(label, baselineY: baselineY, style: style)
  }

  private func lineFlashDrawStyle(buffer: String) -> LineFlashDrawStyle {
    let font = NSFontManager.shared.convert(editorFont, toHaveTrait: .boldFontMask)
      .withSize(editorFont.pointSize)
    return LineFlashDrawStyle(
      font: font,
      defaultAttrs: flashLabelAttributes(font: font, active: false),
      activeAttrs: flashLabelAttributes(font: font, active: true),
      buffer: buffer
    )
  }

  private func flashLabelAttributes(
    font: NSFont,
    active: Bool
  ) -> [NSAttributedString.Key: Any] {
    [
      .font: font,
      .foregroundColor: active
        ? NSColor(red: 0.980, green: 0.702, blue: 0.529, alpha: 1.0)
        : NSColor(red: 0.651, green: 0.890, blue: 0.631, alpha: 1.0)
    ]
  }

  private func attrs(for label: String, style: LineFlashDrawStyle) -> [NSAttributedString.Key: Any] {
    !style.buffer.isEmpty && label.hasPrefix(style.buffer) ? style.activeAttrs : style.defaultAttrs
  }

  private func drawFlashLabel(_ label: String, baselineY: CGFloat, style: LineFlashDrawStyle) {
    let labelString = label as NSString
    let attrs = attrs(for: label, style: style)
    let size = labelString.size(withAttributes: attrs)
    let originY = baselineY - style.font.ascender
    guard originY + size.height > bounds.minY, originY < bounds.maxY else { return }
    labelString.draw(at: NSPoint(x: bounds.width - size.width - 2, y: originY), withAttributes: attrs)
  }
}
