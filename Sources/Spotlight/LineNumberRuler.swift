import AppKit

final class LineNumberRuler: NSRulerView {
  var textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.8)
  var editorFont: NSFont

  private var labelFontSize: CGFloat { max(15, editorFont.pointSize) }

  /// The gutter is non-interactive -- let drags here move the panel
  /// window like the rest of the HUD chrome instead of being swallowed
  /// by `NSRulerView`.
  override var mouseDownCanMoveWindow: Bool { true }

  init(textView: NSTextView, editorFont: NSFont) {
    self.editorFont = editorFont
    super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
    self.clientView = textView
    self.ruleThickness = Self.thickness(forLineCount: 1, labelSize: labelFontSize)

    if let clipView = textView.enclosingScrollView?.contentView {
      clipView.postsBoundsChangedNotifications = true
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(contentDidScroll),
        name: NSView.boundsDidChangeNotification,
        object: clipView
      )
    }
  }

  /// Grow the gutter so the widest visible line number fits inside it.
  /// Called on every text change.
  func updateRequiredThickness() {
    guard let textView = clientView as? NSTextView else { return }
    let lineCount = max(1, textView.string.components(separatedBy: "\n").count)
    let required = Self.thickness(forLineCount: lineCount, labelSize: labelFontSize)
    if abs(ruleThickness - required) > 0.5 {
      ruleThickness = required
      invalidateHashMarks()
    }
  }

  static func thickness(forLineCount lineCount: Int, labelSize: CGFloat) -> CGFloat {
    // Clamp before stringifying so a negative count's "-" doesn't inflate
    // the digit count.
    let effective = max(1, lineCount)
    let digits = String(effective).count
    let font = NSFont.monospacedDigitSystemFont(ofSize: labelSize, weight: .regular)
    let sample = String(repeating: "8", count: digits) as NSString
    let digitWidth = sample.size(withAttributes: [.font: font]).width
    // 2pt right inset + a little left breathing room.
    return ceil(digitWidth) + 6
  }

  /// Total laid-out display rows (line fragments + trailing blank
  /// fragment). Soft-wrapped rows count individually; an empty trailing
  /// line after `\n` counts as one. Clamped to `>= 1` so a fresh buffer
  /// still reports at least one row.
  static func displayRowCount(in textView: NSTextView) -> Int {
    guard let layoutManager = textView.layoutManager,
      let container = textView.textContainer
    else { return 1 }
    layoutManager.ensureLayout(for: container)
    var count = 0
    let fullGlyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
    layoutManager.enumerateLineFragments(forGlyphRange: fullGlyphRange) { _, _, _, _, _ in
      count += 1
    }
    if !layoutManager.extraLineFragmentRect.isEmpty {
      count += 1
    }
    // Immediately after inserting a trailing newline, TextKit can
    // momentarily report no extra fragment even though the logical
    // second line exists. Use logical-line count as a floor so row
    // growth doesn't lag one keystroke behind.
    let logical = max(1, textView.string.components(separatedBy: "\n").count)
    return max(logical, count)
  }

  private static let newlineUnichar: unichar = 10

  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func contentDidScroll() { needsDisplay = true }

  override func draw(_ dirtyRect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.clip(to: visibleRect)
    drawHashMarksAndLabels(in: dirtyRect)
    ctx.restoreGState()
  }

  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let textView = clientView as? NSTextView,
      let layoutManager = textView.layoutManager
    else { return }

    let labelFont = NSFont.monospacedDigitSystemFont(ofSize: labelFontSize, weight: .regular)
    let context = DrawContext(
      textView: textView,
      layoutManager: layoutManager,
      textViewOriginInRuler: convert(NSPoint.zero, from: textView),
      visibleRect: textView.visibleRect,
      insetY: textView.textContainerInset.height,
      labelFont: labelFont,
      attributes: [
        .font: labelFont,
        .foregroundColor: textColor
      ]
    )

    let text = textView.string as NSString
    if let placeholderTextView = textView as? PlaceholderTextView {
      if placeholderTextView.isShowingLineFlashHints {
        drawLineFlashHints(in: context, textView: placeholderTextView, text: text)
        return
      }
    }
    if text.length == 0 {
      drawEmptyBufferNumber(in: context)
      return
    }
    drawLineNumbers(in: context, text: text)
  }

  struct DrawContext {
    let textView: NSTextView
    let layoutManager: NSLayoutManager
    let textViewOriginInRuler: NSPoint
    let visibleRect: NSRect
    let insetY: CGFloat
    let labelFont: NSFont
    let attributes: [NSAttributedString.Key: Any]
  }

  /// Draws `number` so its glyph baseline sits at `baselineY` (ruler coords).
  /// Uses the label font's ascender to translate baseline -> drawing origin.
  private func drawNumber(
    _ number: Int,
    baselineY: CGFloat,
    font: NSFont,
    attrs: [NSAttributedString.Key: Any]
  ) {
    drawString("\(number)" as NSString, baselineY: baselineY, font: font, attrs: attrs)
  }

  private func drawString(
    _ string: NSString,
    baselineY: CGFloat,
    font: NSFont,
    attrs: [NSAttributedString.Key: Any]
  ) {
    let size = string.size(withAttributes: attrs)
    let originY = baselineY - font.ascender
    guard originY + size.height > bounds.minY, originY < bounds.maxY else { return }
    string.draw(at: NSPoint(x: bounds.width - size.width - 2, y: originY), withAttributes: attrs)
  }

  /// Baseline y (in fragment-local coords) that matches what
  /// `FixedLineHeightLayoutManager.setLocation` produces for a glyph
  /// in a fixed-height fragment.
  ///
  /// The layout manager centers each glyph vertically within its fragment,
  /// splitting extra space equally above and below:
  ///
  ///     baseline = font.ascender + (fragmentHeight − fontHeight) / 2
  ///
  /// Used for empty-buffer placeholder, inline math suggestion, extra line
  /// fragment, and anywhere else a baseline is needed without a live glyph.
  /// Must stay in sync with the formula in `setLocation`.
  static func synthesizedBaseline(fragmentHeight: CGFloat, font: NSFont) -> CGFloat {
    let fontHeight = font.ascender - font.descender
    return font.ascender + max(0, fragmentHeight - fontHeight) / 2
  }

  private func drawEmptyBufferNumber(in ctx: DrawContext) {
    let baselineInFragment = Self.synthesizedBaseline(
      fragmentHeight: EditorMetrics.lineHeight,
      font: editorFont
    )
    let baselineInRuler = ctx.insetY + baselineInFragment + ctx.textViewOriginInRuler.y
    drawNumber(1, baselineY: baselineInRuler, font: ctx.labelFont, attrs: ctx.attributes)
  }

  /// Walks every layout line fragment top-to-bottom and draws, for each
  /// one intersecting the visible rect:
  ///   - a line number if the fragment is the first fragment of a logical
  ///     line (its preceding char is `\n` or it starts the buffer), or
  ///   - nothing if the fragment is a soft-wrap continuation.
  ///
  /// Sticky-label exception: if the first row visible in the gutter is a
  /// continuation whose owning line's head has scrolled above
  /// `visibleRect`, the owning line number is drawn there instead of the
  /// wrap marker so the user can always tell which logical line the
  /// current rows belong to. Once the owning line's head scrolls back
  /// into view (or the user types a new logical line), the sticky label
  /// snaps back to its natural position.
  private func drawLineNumbers(in ctx: DrawContext, text: NSString) {
    let lm = ctx.layoutManager
    let all = NSRange(location: 0, length: lm.numberOfGlyphs)
    var lineNumber = 0
    var drewLabel = false
    lm.enumerateLineFragments(forGlyphRange: all) { frag, _, _, glyphs, stop in
      let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
      let start =
        chars.location == 0
        || text.character(at: chars.location - 1) == Self.newlineUnichar
      if start { lineNumber += 1 }
      if frag.origin.y >= ctx.visibleRect.maxY {
        stop.pointee = true
        return
      }
      guard frag.maxY > ctx.visibleRect.minY else { return }
      let offset = lm.location(forGlyphAt: glyphs.location).y
      let baselineY = frag.origin.y + offset + ctx.insetY + ctx.textViewOriginInRuler.y
      if start || !drewLabel {
        self.drawNumber(
          lineNumber,
          baselineY: baselineY,
          font: ctx.labelFont,
          attrs: ctx.attributes
        )
        drewLabel = true
      }
    }
    drawExtraLineFragmentLabel(previousLineNumber: lineNumber, ctx: ctx, text: text)
  }

  /// The trailing blank fragment for text ending in `\n` is a fresh
  /// logical line, never a wrap continuation -- always gets a number one
  /// greater than the last fragment's.
  private func drawExtraLineFragmentLabel(previousLineNumber: Int, ctx: DrawContext, text: NSString) {
    guard text.hasSuffix("\n") else { return }
    let extra = ctx.layoutManager.extraLineFragmentRect
    guard !extra.isEmpty,
      extra.maxY > ctx.visibleRect.minY,
      extra.origin.y < ctx.visibleRect.maxY
    else { return }
    let offset = Self.synthesizedBaseline(fragmentHeight: extra.height, font: editorFont)
    let baselineY = extra.origin.y + offset + ctx.insetY + ctx.textViewOriginInRuler.y
    drawNumber(
      previousLineNumber + 1,
      baselineY: baselineY,
      font: ctx.labelFont,
      attrs: ctx.attributes
    )
  }
}

private struct LineFlashDrawStyle {
  let font: NSFont
  let defaultAttrs: [NSAttributedString.Key: Any]
  let activeAttrs: [NSAttributedString.Key: Any]
  let defaultFill: NSColor
  let activeFill: NSColor
  let buffer: String
}

extension LineNumberRuler {
  private func drawLineFlashHints(
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
    let style = lineFlashDrawStyle(textView: textView)
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

  private func lineFlashDrawStyle(textView: PlaceholderTextView) -> LineFlashDrawStyle {
    let font = NSFontManager.shared.convert(editorFont, toHaveTrait: .boldFontMask)
      .withSize(editorFont.pointSize)
    let flash = textView.editorTheme.flash
    return LineFlashDrawStyle(
      font: font,
      defaultAttrs: flashLabelAttributes(font: font, textColor: NSColor(flash.labelText)),
      activeAttrs: flashLabelAttributes(font: font, textColor: NSColor(flash.activeLabelText)),
      defaultFill: NSColor(flash.labelFill),
      activeFill: NSColor(flash.activeLabelFill),
      buffer: textView.flashLabelBuffer
    )
  }

  private func flashLabelAttributes(
    font: NSFont,
    textColor: NSColor
  ) -> [NSAttributedString.Key: Any] {
    [
      .font: font,
      .foregroundColor: textColor
    ]
  }

  private func attrs(for label: String, style: LineFlashDrawStyle) -> [NSAttributedString.Key: Any] {
    !style.buffer.isEmpty && label.hasPrefix(style.buffer) ? style.activeAttrs : style.defaultAttrs
  }

  private func drawFlashLabel(_ label: String, baselineY: CGFloat, style: LineFlashDrawStyle) {
    let attrs = attrs(for: label, style: style)
    let fill = fillColor(for: label, style: style)
    let labelString = label as NSString
    let labelSize = labelString.size(withAttributes: attrs)
    let rect = NSRect(
      x: bounds.width - labelSize.width - 6,
      y: baselineY - style.font.ascender - 1,
      width: labelSize.width + 6,
      height: style.font.ascender - style.font.descender + 2
    )
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
    let point = NSPoint(x: rect.midX - labelSize.width / 2, y: baselineY - style.font.ascender)
    labelString.draw(at: point, withAttributes: attrs)
  }

  private func fillColor(for label: String, style: LineFlashDrawStyle) -> NSColor {
    !style.buffer.isEmpty && label.hasPrefix(style.buffer) ? style.activeFill : style.defaultFill
  }
}
