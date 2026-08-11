import AppKit

/// nvim-parity vim rendering the view owns itself: the reverse-video
/// block cursor, the Visual selection band, and the yank flash.
///
/// The view paints the visual band in `drawBackground` because AppKit
/// substitutes `unemphasizedSelectedTextBackgroundColor` (a light gray)
/// for `selectedTextAttributes` whenever the view is not first
/// responder -- David's captures showed that gray as the visual-mode
/// look. An opaque fill of the nvim blend over the native paint keeps
/// the band identical in every key state.
extension PlaceholderTextView {
  // MARK: - Block cursor (nvim: Cursor bg=cursor fg=base)

  /// Fill a block-cursor cell and flip the covered glyph to the surface
  /// color, exactly like his nvim's `Cursor` group (reverse video). The
  /// old 0.82-alpha wash left the glyph half-visible through an
  /// accent-colored block.
  func fillVimBlockCursor(_ rect: NSRect, coveringCharAt index: Int?) {
    (editorVimBlockCursorColor ?? Self.normalModeCursorColor).setFill()
    rect.fill()
    guard let index, let surface = editorSurfaceColor else { return }
    let nsString = string as NSString
    guard index >= 0, index < nsString.length else { return }
    let charRange = nsString.rangeOfComposedCharacterSequence(at: index)
    let glyphText = nsString.substring(with: charRange)
    guard glyphText != "\n" else { return }
    let glyphFont = font ?? .systemFont(ofSize: 14)
    (glyphText as NSString).draw(
      at: rect.origin,
      withAttributes: [.font: glyphFont, .foregroundColor: surface]
    )
  }

  // MARK: - Yank flash painting

  override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    drawYankFlash(in: rect)
  }

  /// True while the vim visual band should replace the native selection
  /// paint (see FixedLineHeightLayoutManager.fillBackgroundRectArray).
  var vimVisualBandActive: Bool {
    guard let engine = vimEngine else { return false }
    return (engine.mode == .visual || engine.mode == .visualLine) && selectedRange.length > 0
  }

  private func enclosingRects(forCharacterRange charRange: NSRange) -> [NSRect] {
    guard let layoutManager, let textContainer else { return [] }
    let clamped = NSIntersectionRange(
      charRange,
      NSRange(location: 0, length: (string as NSString).length)
    )
    guard clamped.length > 0 else { return [] }
    let glyphRange = layoutManager.glyphRange(
      forCharacterRange: clamped,
      actualCharacterRange: nil
    )
    var rects: [NSRect] = []
    layoutManager.enumerateEnclosingRects(
      forGlyphRange: glyphRange,
      withinSelectedGlyphRange: glyphRange,
      in: textContainer
    ) { rect, _ in
      rects.append(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
    }
    return rects
  }

  // MARK: - Yank flash (nvim: vim.hl.on_yank higroup=Visual timeout=300)

  /// David's own nvim flashes yanked text with the Visual band for
  /// 300ms (config/autocmds.lua). Same band, same clock -- held for the
  /// first half, faded out over the second instead of nvim's hard cut.
  func flashYankHighlight(over range: NSRange) {
    guard range.length > 0, editorVisualSelectionColor != nil else { return }
    yankFlashRange = range
    yankFlashAlpha = 1
    yankFlashGeneration += 1
    invalidateYankFlashRects()
    let generation = yankFlashGeneration
    let started = CACurrentMediaTime()
    Task { @MainActor [weak self] in
      while let self, self.yankFlashGeneration == generation {
        let elapsed = CACurrentMediaTime() - started
        guard elapsed < 0.3 else {
          self.clearYankFlash()
          break
        }
        self.yankFlashAlpha = elapsed <= 0.15 ? 1 : 1 - (elapsed - 0.15) / 0.15
        self.invalidateYankFlashRects()
        try? await Task.sleep(nanoseconds: 16_000_000)
      }
    }
  }

  func clearYankFlash() {
    guard yankFlashRange != nil else { return }
    invalidateYankFlashRects()
    yankFlashRange = nil
    yankFlashAlpha = 0
    yankFlashGeneration += 1
  }

  /// Any edit invalidates the flashed span (nvim's extmark just moves;
  /// a stale NSRange would band the wrong text).
  override func didChangeText() {
    super.didChangeText()
    clearYankFlash()
  }

  private func drawYankFlash(in dirtyRect: NSRect) {
    guard let range = yankFlashRange, yankFlashAlpha > 0,
      let color = editorVisualSelectionColor
    else { return }
    color.withAlphaComponent(yankFlashAlpha).setFill()
    for rect in enclosingRects(forCharacterRange: range) where rect.intersects(dirtyRect) {
      rect.fill()
    }
  }

  private func invalidateYankFlashRects() {
    guard let range = yankFlashRange else { return }
    for rect in enclosingRects(forCharacterRange: range) {
      setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
    }
  }
}
