import AppKit

final class LineNumberRuler: NSRulerView {
  static let defaultTextAlpha: CGFloat = 0.42

  var textColor = NSColor.secondaryLabelColor.withAlphaComponent(defaultTextAlpha)
  var editorFont: NSFont
  var showsLineNumbers: Bool {
    didSet {
      guard oldValue != showsLineNumbers else { return }
      updateRequiredThickness()
      needsDisplay = true
    }
  }

  static let labelFontSize: CGFloat = EditorMetrics.fontSize

  /// The gutter is non-interactive -- let drags here move the panel
  /// window like the rest of the HUD chrome instead of being swallowed
  /// by `NSRulerView`.
  override var mouseDownCanMoveWindow: Bool { true }

  init(textView: NSTextView, editorFont: NSFont, showsLineNumbers: Bool = false) {
    self.editorFont = editorFont
    self.showsLineNumbers = showsLineNumbers
    super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
    self.clientView = textView
    self.ruleThickness = Self.thickness(
      forLineCount: 1,
      labelSize: Self.labelFontSize,
      showsLineNumbers: showsLineNumbers
    )

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

  /// Grow or shrink the gutter for the current hidden / numeric-label mode.
  /// Called on every text change.
  func updateRequiredThickness() {
    guard let textView = clientView as? NSTextView else { return }
    let lineCount = max(1, textView.string.components(separatedBy: "\n").count)
    let required = Self.thickness(
      forLineCount: lineCount,
      labelSize: Self.labelFontSize,
      showsLineNumbers: showsLineNumbers
    )
    if abs(ruleThickness - required) > 0.5 {
      ruleThickness = required
      invalidateHashMarks()
    }
  }

  static func thickness(
    forLineCount lineCount: Int,
    labelSize: CGFloat,
    showsLineNumbers: Bool = false
  ) -> CGFloat {
    guard showsLineNumbers else {
      return 0
    }
    // Clamp before stringifying so a negative count's "-" doesn't inflate
    // the digit count.
    let effective = max(1, lineCount)
    let digits = String(effective).count
    let font = Self.labelFont(ofSize: labelSize)
    let sample = String(repeating: "8", count: digits) as NSString
    let digitWidth = sample.size(withAttributes: [.font: font]).width
    // Continuation rows render `wrapMarker` in place of a number. Ensure
    // the gutter is wide enough for either glyph.
    let wrapWidth = Self.wrapMarker.size(withAttributes: [.font: font]).width
    // Nvim-style signcolumn: one narrow sign cell on the left, one
    // right-aligned number column on the right.
    return Self.signColumnWidth(forLabelSize: labelSize) + ceil(max(digitWidth, wrapWidth)) + 6
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

  /// Logical line index for the text row that begins at `location`.
  ///
  /// `NSLayoutManager.enumerateLineFragments` only visits glyph-bearing
  /// rows, so blank lines have no fragment of their own. Counting newlines
  /// before each fragment keeps gutter markers aligned after edits such as
  /// Vim `o` on `## To Do`, which inserts an empty logical line before the
  /// first checklist task.
  static func logicalLineIndex(forFragmentStartingAt location: Int, in text: NSString) -> Int {
    let clamped = min(max(0, location), text.length)
    guard clamped > 0 else { return 0 }
    var count = 0
    for index in 0..<clamped where text.character(at: index) == newlineUnichar {
      count += 1
    }
    return count
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

    let labelFont = Self.labelFont(ofSize: Self.labelFontSize)
    let context = DrawContext(
      textView: textView,
      layoutManager: layoutManager,
      textViewOriginInRuler: convert(NSPoint.zero, from: textView),
      visibleRect: textView.visibleRect,
      insetY: textView.textContainerInset.height,
      showsLineNumbers: showsLineNumbers,
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

  struct DrawContext {
    let textView: NSTextView
    let layoutManager: NSLayoutManager
    let textViewOriginInRuler: NSPoint
    let visibleRect: NSRect
    let insetY: CGFloat
    let showsLineNumbers: Bool
    let labelFont: NSFont
    let attributes: [NSAttributedString.Key: Any]
    let wrapAttributes: [NSAttributedString.Key: Any]
  }

  static func labelFont(ofSize size: CGFloat) -> NSFont {
    SpotNoteFont.editor(size: size)
  }

  private var numberColumnRightX: CGFloat { bounds.width - 2 }

}

extension LineNumberRuler {
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
    string.draw(at: NSPoint(x: numberColumnRightX - size.width, y: originY), withAttributes: attrs)
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
    guard ctx.showsLineNumbers else { return }
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
      let start = self.isFirstVisibleFragment(chars: chars, text: text)
      if start {
        lineNumber = Self.logicalLineIndex(forFragmentStartingAt: chars.location, in: text) + 1
      }
      if frag.origin.y >= ctx.visibleRect.maxY {
        stop.pointee = true
        return
      }
      guard frag.maxY > ctx.visibleRect.minY else { return }
      let offset = lm.location(forGlyphAt: glyphs.location).y
      let baselineY = frag.origin.y + offset + ctx.insetY + ctx.textViewOriginInRuler.y
      if start || !drewLabel {
        self.drawLineLabel(
          lineNumber: lineNumber,
          baselineY: baselineY,
          ctx: ctx
        )
        drewLabel = true
      } else if ctx.showsLineNumbers {
        self.drawWrapMarker(baselineY: baselineY, font: ctx.labelFont, attrs: ctx.wrapAttributes)
      }
    }
    drawExtraLineFragmentLabel(ctx: ctx, text: text)
  }

  private func drawLineLabel(
    lineNumber: Int,
    baselineY: CGFloat,
    ctx: DrawContext
  ) {
    if ctx.showsLineNumbers {
      drawNumber(lineNumber, baselineY: baselineY, font: ctx.labelFont, attrs: ctx.attributes)
    }
  }

  /// The trailing blank fragment for text ending in `\n` is a fresh
  /// logical line, never a wrap continuation -- always gets a number one
  /// greater than the last fragment's.
  private func drawExtraLineFragmentLabel(
    ctx: DrawContext,
    text: NSString
  ) {
    let extra = ctx.layoutManager.extraLineFragmentRect
    guard text.hasSuffix("\n"), !extra.isEmpty,
      extra.maxY > ctx.visibleRect.minY, extra.origin.y < ctx.visibleRect.maxY
    else { return }
    let offset = Self.synthesizedBaseline(fragmentHeight: extra.height, font: editorFont)
    let baselineY = extra.origin.y + offset + ctx.insetY + ctx.textViewOriginInRuler.y
    let lineIndex = Self.logicalLineIndex(forFragmentStartingAt: text.length, in: text)
    if ctx.showsLineNumbers {
      drawNumber(
        lineIndex + 1,
        baselineY: baselineY,
        font: ctx.labelFont,
        attrs: ctx.attributes
      )
    }
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
      at: NSPoint(x: numberColumnRightX - size.width, y: originY),
      withAttributes: attrs
    )
  }

  private func isFirstVisibleFragment(chars: NSRange, text: NSString) -> Bool {
    chars.location == 0
      || text.character(at: chars.location - 1) == Self.newlineUnichar
  }
}
