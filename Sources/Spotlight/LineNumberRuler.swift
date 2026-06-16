import AppKit

final class LineNumberRuler: NSRulerView {
  var textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.8)
  var editorFont: NSFont

  static let labelFontSize: CGFloat = EditorMetrics.fontSize

  /// The gutter is non-interactive -- let drags here move the panel
  /// window like the rest of the HUD chrome instead of being swallowed
  /// by `NSRulerView`.
  override var mouseDownCanMoveWindow: Bool { true }

  init(textView: NSTextView, editorFont: NSFont) {
    self.editorFont = editorFont
    super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
    self.clientView = textView
    self.ruleThickness = Self.thickness(forLineCount: 1, labelSize: Self.labelFontSize)

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
    let required = Self.thickness(forLineCount: lineCount, labelSize: Self.labelFontSize)
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
    // Continuation rows render `wrapMarker` in place of a number. Ensure
    // the gutter is wide enough for either glyph.
    let markerWidth = Self.wrapMarker.size(withAttributes: [.font: font]).width
    // 2pt right inset + a little left breathing room.
    return ceil(max(digitWidth, markerWidth)) + 6
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

  /// Glyph shown in place of a number on soft-wrapped continuation rows.
  /// Kept as a `NSString` constant so `thickness` and the drawing path
  /// agree on the width.
  private static let wrapMarker: NSString = "↪"
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

    let labelFont = NSFont.monospacedDigitSystemFont(ofSize: Self.labelFontSize, weight: .regular)
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
      ],
      wrapAttributes: [
        .font: labelFont,
        .foregroundColor: textColor.withAlphaComponent(0.45)
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
    drawLineNumbersAndWrapMarkers(in: context, text: text)
  }

  private struct DrawContext {
    let textView: NSTextView
    let layoutManager: NSLayoutManager
    let textViewOriginInRuler: NSPoint
    let visibleRect: NSRect
    let insetY: CGFloat
    let labelFont: NSFont
    let attributes: [NSAttributedString.Key: Any]
    let wrapAttributes: [NSAttributedString.Key: Any]
  }

  /// Draws `number` so its glyph baseline sits at `baselineY` (ruler coords).
  /// Uses the label font's ascender to translate baseline -> drawing origin.
  private func drawNumber(
    _ number: Int,
    baselineY: CGFloat,
    font: NSFont,
    attrs: [NSAttributedString.Key: Any]
  ) {
    let string = "\(number)" as NSString
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
  ///   - `wrapMarker` if the fragment is a soft-wrap continuation.
  ///
  /// Sticky-label exception: if the first row visible in the gutter is a
  /// continuation whose owning line's head has scrolled above
  /// `visibleRect`, the owning line number is drawn there instead of the
  /// wrap marker so the user can always tell which logical line the
  /// current rows belong to. Once the owning line's head scrolls back
  /// into view (or the user types a new logical line), the sticky label
  /// snaps back to its natural position.
  private func drawLineNumbersAndWrapMarkers(in ctx: DrawContext, text: NSString) {
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
      } else {
        self.drawWrapMarker(baselineY: baselineY, font: ctx.labelFont, attrs: ctx.wrapAttributes)
      }
    }
    drawExtraLineFragmentLabel(previousLineNumber: lineNumber, ctx: ctx, text: text)
  }

  /// The trailing blank fragment for text ending in `\n` is a fresh
  /// logical line, never a wrap continuation -- always gets a number one
  /// greater than the last fragment's.
  private func drawExtraLineFragmentLabel(
    previousLineNumber: Int,
    ctx: DrawContext,
    text: NSString
  ) {
    let extra = ctx.layoutManager.extraLineFragmentRect
    guard text.hasSuffix("\n"), !extra.isEmpty,
      extra.maxY > ctx.visibleRect.minY, extra.origin.y < ctx.visibleRect.maxY
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

  private func drawWrapMarker(
    baselineY: CGFloat,
    font: NSFont,
    attrs: [NSAttributedString.Key: Any]
  ) {
    let size = Self.wrapMarker.size(withAttributes: attrs)
    let originY = baselineY - font.ascender
    guard originY + size.height > bounds.minY, originY < bounds.maxY else { return }
    Self.wrapMarker.draw(
      at: NSPoint(x: bounds.width - size.width - 2, y: originY),
      withAttributes: attrs
    )
  }
}

private struct LineFlashDrawStyle {
  let font: NSFont
  let defaultAttrs: [NSAttributedString.Key: Any]
  let activeAttrs: [NSAttributedString.Key: Any]
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
