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
///
/// YANK FLASH -- "scan, lift, dissolve" (2026-08-11). A yank is an
/// EVENT, not a state, so it no longer wears the Visual band: the
/// event wears the block cursor's rosewater identity instead.
/// - Scan: a soft-edged rosewater glow sweeps the span left to right
///   (ease-out), the register "reading" the text.
/// - Lift: the yanked glyphs themselves -- the real glyph run, redrawn
///   through the layout manager -- rise and dissolve, the copy visibly
///   leaving for the register.
/// - Dissolve: the glow settles out on an ease-out decay, never linear.
/// The glow paints UNDER the text (`drawBackground`), the ghost OVER it
/// (`draw`), and all timing lives in `YankFlashCurve` as pure sampled
/// functions so every beat is testable without a display.

/// One sampled animation frame.
struct YankFlashFrame: Equatable {
  /// 0...1 position of the scan's leading edge across the span.
  var sweep: CGFloat
  /// 0...1 glow intensity behind the edge.
  var glow: CGFloat
  /// Upward travel of the ghost glyphs, in points.
  var ghostRise: CGFloat
  /// 0...1 ghost opacity (scaled by `ghostPeakAlpha` at draw time).
  var ghostAlpha: CGFloat
}

/// Pure timing. `sample(at:)` is the whole animation: the drawing code
/// holds no clocks or easing of its own.
enum YankFlashCurve {
  static let duration: TimeInterval = 0.43
  static let sweepDuration: TimeInterval = 0.13
  /// The glow holds at peak until here, then dissolves.
  static let holdUntil: TimeInterval = 0.19
  static let ghostStart: TimeInterval = 0.05
  static let ghostDuration: TimeInterval = 0.33
  /// Total upward travel of the ghost, in points.
  static let ghostTravel: CGFloat = 14
  /// Peak glow alpha over the surface; the rosewater roles are bright,
  /// so the glow stays a wash, never a slab.
  static let peakGlowAlpha: CGFloat = 0.24
  static let ghostPeakAlpha: CGFloat = 0.5
  /// Width of the scan's soft leading edge, in points.
  static let sweepSoftEdge: CGFloat = 26
  /// Beyond this many yanked characters the ghost is skipped (a yG of a
  /// huge note would redraw the whole run every frame); the glow plays.
  static let ghostCharacterCap = 1500

  /// nil once the animation has finished.
  static func sample(at elapsed: TimeInterval) -> YankFlashFrame? {
    guard elapsed < duration else { return nil }
    let time = max(0, elapsed)
    let scanT = min(time / sweepDuration, 1)
    let sweep = 1 - (1 - scanT) * (1 - scanT)
    let glow: Double
    if time <= holdUntil {
      glow = sweep
    } else {
      let decayT = (time - holdUntil) / (duration - holdUntil)
      glow = pow(1 - decayT, 1.7)
    }
    var rise: Double = 0
    var ghostAlpha: Double = 0
    if time > ghostStart {
      let liftT = min((time - ghostStart) / ghostDuration, 1)
      rise = Double(ghostTravel) * (1 - pow(1 - liftT, 3))
      ghostAlpha = liftT >= 1 ? 0 : pow(1 - liftT, 1.35)
    }
    return YankFlashFrame(
      sweep: CGFloat(sweep),
      glow: CGFloat(glow),
      ghostRise: CGFloat(rise),
      ghostAlpha: CGFloat(ghostAlpha)
    )
  }
}

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

  // MARK: - Visual band

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

  // MARK: - Yank flash

  func flashYankHighlight(over range: NSRange) {
    guard range.length > 0 else { return }
    yankFlashRange = range
    yankFlashFrame = YankFlashCurve.sample(at: 0)
    yankFlashGeneration += 1
    invalidateYankFlashRects()
    let generation = yankFlashGeneration
    let started = CACurrentMediaTime()
    Task { @MainActor [weak self] in
      while let self, self.yankFlashGeneration == generation {
        guard let frame = YankFlashCurve.sample(at: CACurrentMediaTime() - started) else {
          self.clearYankFlash()
          break
        }
        self.yankFlashFrame = frame
        self.invalidateYankFlashRects()
        try? await Task.sleep(nanoseconds: 16_000_000)
      }
    }
  }

  func clearYankFlash() {
    guard yankFlashRange != nil else { return }
    invalidateYankFlashRects()
    yankFlashRange = nil
    yankFlashFrame = nil
    yankFlashGeneration += 1
  }

  /// Any edit invalidates the flashed span (nvim's extmark just moves;
  /// a stale NSRange would band the wrong text). Same for search bands.
  override func didChangeText() {
    super.didChangeText()
    clearYankFlash()
    if !vimSearchMatches.isEmpty || vimSearchCommitted {
      clearVimSearch()
      vimController?.clearSearchStatus()
    }
  }

  /// The event color: the block cursor's rosewater identity, never the
  /// Visual band (selection is state; a yank is an event).
  func yankGlowColor(intensity: CGFloat) -> NSColor {
    (editorVimBlockCursorColor ?? Self.normalModeCursorColor)
      .withAlphaComponent(YankFlashCurve.peakGlowAlpha * intensity)
  }

  /// The ghost redraws the real glyph run every frame; a pathological
  /// span (yG of a huge note) plays glow-only.
  var yankGhostEligible: Bool {
    guard let range = yankFlashRange else { return false }
    return range.length <= YankFlashCurve.ghostCharacterCap
  }

  override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    drawVimSearchBands(in: rect)
    drawYankGlow(in: rect)
  }

  /// The scan: one soft-edged wipe across the span's union -- every
  /// line lights left to right together, clipped to the glow path.
  private func drawYankGlow(in dirtyRect: NSRect) {
    guard let range = yankFlashRange, let frame = yankFlashFrame, frame.glow > 0 else { return }
    let rects = enclosingRects(forCharacterRange: range)
    guard let first = rects.first else { return }
    let bounds = rects.dropFirst().reduce(first) { $0.union($1) }
    guard bounds.insetBy(dx: -2, dy: -2).intersects(dirtyRect) else { return }
    let color = yankGlowColor(intensity: frame.glow)
    NSGraphicsContext.current?.saveGraphicsState()
    yankGlowPath(for: rects, union: bounds).addClip()
    let soft = YankFlashCurve.sweepSoftEdge
    let edgeX = bounds.minX + frame.sweep * (bounds.width + soft)
    let solidWidth = max(0, edgeX - soft - bounds.minX)
    color.setFill()
    NSRect(x: bounds.minX, y: bounds.minY, width: solidWidth, height: bounds.height).fill()
    if edgeX - soft < bounds.maxX {
      let slice = NSRect(x: edgeX - soft, y: bounds.minY, width: soft, height: bounds.height)
      NSGradient(colors: [color, color.withAlphaComponent(0)])?.draw(in: slice, angle: 0)
    }
    NSGraphicsContext.current?.restoreGraphicsState()
  }

  /// Rounded corners where the shape allows: a single line or an
  /// aligned linewise block rounds as one; a ragged charwise multi-line
  /// span stays square (per-line rounding pinches at the joins).
  private func yankGlowPath(for rects: [NSRect], union: NSRect) -> NSBezierPath {
    let radius: CGFloat = 4
    guard let first = rects.first else { return NSBezierPath() }
    if rects.count == 1 {
      return NSBezierPath(roundedRect: first, xRadius: radius, yRadius: radius)
    }
    let aligned = rects.allSatisfy {
      abs($0.minX - first.minX) < 0.5 && abs($0.width - first.width) < 0.5
    }
    if aligned {
      return NSBezierPath(roundedRect: union, xRadius: radius, yRadius: radius)
    }
    let path = NSBezierPath()
    for rect in rects {
      path.appendRect(rect)
    }
    return path
  }

  /// The lift: the yanked glyphs redrawn in their true colors, risen
  /// and dissolving. Called from `draw(_:)` so the ghost floats OVER
  /// the live text.
  func drawYankGhost(in dirtyRect: NSRect) {
    guard let range = yankFlashRange, let frame = yankFlashFrame,
      frame.ghostAlpha > 0.01, yankGhostEligible,
      let layoutManager, let ctx = NSGraphicsContext.current?.cgContext
    else { return }
    let rects = enclosingRects(forCharacterRange: range)
    guard let first = rects.first else { return }
    let bounds = rects.dropFirst().reduce(first) { $0.union($1) }
    let risen = bounds.offsetBy(dx: 0, dy: -frame.ghostRise).insetBy(dx: -2, dy: -2)
    guard risen.intersects(dirtyRect) else { return }
    let clamped = NSIntersectionRange(
      range,
      NSRange(location: 0, length: (string as NSString).length)
    )
    guard clamped.length > 0 else { return }
    let glyphRange = layoutManager.glyphRange(
      forCharacterRange: clamped,
      actualCharacterRange: nil
    )
    ctx.saveGState()
    ctx.translateBy(x: 0, y: -frame.ghostRise)
    ctx.setAlpha(frame.ghostAlpha * YankFlashCurve.ghostPeakAlpha)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textContainerOrigin)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
  }

  private func invalidateYankFlashRects() {
    guard let range = yankFlashRange else { return }
    let travel = YankFlashCurve.ghostTravel + 2
    for rect in enclosingRects(forCharacterRange: range) {
      setNeedsDisplay(rect.insetBy(dx: -2, dy: -2).union(rect.offsetBy(dx: 0, dy: -travel)))
    }
  }
}
