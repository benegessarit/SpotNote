import AppKit

/// Zero-width gutter that materializes only while vim line-flash hints are
/// active: the bold jump labels draw here, in the Raycast 37pt leading gap,
/// and the gutter collapses back to nothing when the hints dismiss. Line
/// numbers were removed (Raycast Notes has no gutter); this ruler exists
/// for the flash-hint labels and the shared layout helpers.
final class LineNumberRuler: NSRulerView {
  static let labelFontSize: CGFloat = EditorMetrics.fontSize

  var editorFont: NSFont

  /// The gutter is non-interactive -- let drags here move the panel
  /// window like the rest of the HUD chrome instead of being swallowed
  /// by `NSRulerView`.
  override var mouseDownCanMoveWindow: Bool { true }

  init(textView: NSTextView, editorFont: NSFont) {
    self.editorFont = editorFont
    super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
    self.clientView = textView
    self.ruleThickness = 0

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

  /// Grow the gutter while line-flash hints show; collapse it otherwise.
  /// Called on every text change and on flash-hint state changes.
  func updateRequiredThickness() {
    guard let textView = clientView as? NSTextView else { return }
    let showingHints = (textView as? PlaceholderTextView)?.isShowingLineFlashHints == true
    let required = Self.thickness(showsLineFlashHints: showingHints, labelSize: Self.labelFontSize)
    if abs(ruleThickness - required) > 0.5 {
      ruleThickness = required
      invalidateHashMarks()
    }
  }

  static func thickness(showsLineFlashHints: Bool, labelSize: CGFloat) -> CGFloat {
    showsLineFlashHints ? Self.signColumnWidth(forLabelSize: labelSize) : 0
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
    guard let textView = clientView as? PlaceholderTextView,
      let layoutManager = textView.layoutManager,
      textView.isShowingLineFlashHints
    else { return }

    let context = DrawContext(
      textView: textView,
      layoutManager: layoutManager,
      textViewOriginInRuler: convert(NSPoint.zero, from: textView),
      visibleRect: textView.visibleRect,
      insetY: textView.textContainerInset.height
    )
    drawLineFlashHints(in: context, textView: textView, text: textView.string as NSString)
  }

  struct DrawContext {
    let textView: NSTextView
    let layoutManager: NSLayoutManager
    let textViewOriginInRuler: NSPoint
    let visibleRect: NSRect
    let insetY: CGFloat
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
}
