import AppKit

/// HoverPeek-parity geometry (decoded from the 21st.dev component): a
/// 200x125 site snapshot in a 2px frame, 8px outer / 5px inner radius,
/// 1px border, the Tailwind shadow-lg two-shadow stack, spring flip-in
/// over an 800px perspective, mouse-follow x at 0.3 gain, and a 100px
/// magnifier lens at 1.75x while hovering the open card.
enum LinkPreviewMetrics {
  static let imageSize = NSSize(width: 200, height: 125)
  static let framePadding: CGFloat = 2
  static let borderWidth: CGFloat = 1
  static let outerRadius: CGFloat = 8
  static let innerRadius: CGFloat = 5
  /// Radix sideOffset: gap between the link's line and the card bottom.
  static let sideOffset: CGFloat = 12
  static let openDelay: TimeInterval = 0.075
  static let closeDelay: TimeInterval = 0.15
  static let followGain: CGFloat = 0.3
  static let lensDiameter: CGFloat = 100
  static let lensZoom: CGFloat = 1.75
  static let perspective: CGFloat = 800

  static var cardSize: NSSize {
    let inset = 2 * (framePadding + borderWidth)
    return NSSize(width: imageSize.width + inset, height: imageSize.height + inset)
  }

  /// Container the card centers in -- matched by the pixel-goal reference
  /// capture (280x200), with room for the shadow stack and follow travel.
  static let containerSize = NSSize(width: 280, height: 200)

  static func cardRect(in bounds: NSRect) -> NSRect {
    NSRect(
      x: bounds.minX + (bounds.width - cardSize.width) / 2,
      y: bounds.minY + (bounds.height - cardSize.height) / 2,
      width: cardSize.width,
      height: cardSize.height
    )
  }

  static func imageRect(in bounds: NSRect) -> NSRect {
    cardRect(in: bounds).insetBy(
      dx: framePadding + borderWidth,
      dy: framePadding + borderWidth
    )
  }
}

/// Theme mapping for the card chrome. Dark themes lift the note surface
/// toward the text ink (the neutral-900-on-near-black relationship of the
/// source component); light themes keep the component's white frame.
enum LinkPreviewPalette {
  static func frame(for theme: Theme) -> NSColor {
    theme.mode == .dark
      ? blend(NSColor(theme.background), toward: NSColor(theme.text), fraction: 0.08)
      : .white
  }

  static func well(for theme: Theme) -> NSColor {
    theme.mode == .dark
      ? blend(NSColor(theme.background), toward: NSColor(theme.text), fraction: 0.14)
      : NSColor(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255, alpha: 1)
  }

  static func border(for theme: Theme) -> NSColor {
    NSColor(theme.border)
  }

  static func blend(_ base: NSColor, toward target: NSColor, fraction: CGFloat) -> NSColor {
    let from = base.usingColorSpace(.sRGB) ?? base
    let to = target.usingColorSpace(.sRGB) ?? target
    return NSColor(
      red: from.redComponent + (to.redComponent - from.redComponent) * fraction,
      green: from.greenComponent + (to.greenComponent - from.greenComponent) * fraction,
      blue: from.blueComponent + (to.blueComponent - from.blueComponent) * fraction,
      alpha: 1
    )
  }
}

/// Chrome painting shared by the live card view and the pixel-goal probe
/// render -- one deterministic paint path, no window required.
enum LinkPreviewChrome {
  static func draw(bounds: NSRect, theme: Theme, snapshot: NSImage?, failed: Bool) {
    let card = LinkPreviewMetrics.cardRect(in: bounds)
    let frameColor = LinkPreviewPalette.frame(for: theme)
    // Tailwind shadow-lg: 0 10px 15px -3px + 0 4px 6px -4px at 10% black.
    // NSShadow has no spread, so each pass insets the silhouette instead.
    drawShadowPass(card: card, offsetY: -10, blur: 15, spread: -3, fill: frameColor)
    drawShadowPass(card: card, offsetY: -4, blur: 6, spread: -4, fill: frameColor)
    let outer = NSBezierPath(
      roundedRect: card,
      xRadius: LinkPreviewMetrics.outerRadius,
      yRadius: LinkPreviewMetrics.outerRadius
    )
    frameColor.setFill()
    outer.fill()
    drawWell(bounds: bounds, theme: theme, snapshot: snapshot, failed: failed)
    let borderInset = LinkPreviewMetrics.borderWidth / 2
    let border = NSBezierPath(
      roundedRect: card.insetBy(dx: borderInset, dy: borderInset),
      xRadius: LinkPreviewMetrics.outerRadius - borderInset,
      yRadius: LinkPreviewMetrics.outerRadius - borderInset
    )
    border.lineWidth = LinkPreviewMetrics.borderWidth
    LinkPreviewPalette.border(for: theme).setStroke()
    border.stroke()
  }

  private static func drawShadowPass(
    card: NSRect,
    offsetY: CGFloat,
    blur: CGFloat,
    spread: CGFloat,
    fill: NSColor
  ) {
    guard let context = NSGraphicsContext.current else { return }
    context.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: offsetY)
    shadow.shadowBlurRadius = blur
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.1)
    shadow.set()
    let silhouette = NSBezierPath(
      roundedRect: card.insetBy(dx: -spread, dy: -spread),
      xRadius: LinkPreviewMetrics.outerRadius,
      yRadius: LinkPreviewMetrics.outerRadius
    )
    fill.setFill()
    silhouette.fill()
    context.restoreGraphicsState()
  }

  private static func drawWell(bounds: NSRect, theme: Theme, snapshot: NSImage?, failed: Bool) {
    let imageRect = LinkPreviewMetrics.imageRect(in: bounds)
    let well = NSBezierPath(
      roundedRect: imageRect,
      xRadius: LinkPreviewMetrics.innerRadius,
      yRadius: LinkPreviewMetrics.innerRadius
    )
    LinkPreviewPalette.well(for: theme).setFill()
    well.fill()
    if let snapshot {
      NSGraphicsContext.current?.saveGraphicsState()
      well.addClip()
      snapshot.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
      NSGraphicsContext.current?.restoreGraphicsState()
    } else if failed {
      let text = "Preview unavailable"
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor(theme.placeholder)
      ]
      let size = text.size(withAttributes: attributes)
      text.draw(
        at: NSPoint(
          x: imageRect.midX - size.width / 2,
          y: imageRect.midY - size.height / 2
        ),
        withAttributes: attributes
      )
    }
  }
}

/// The card itself: chrome via `LinkPreviewChrome`, animated behavior
/// (flip, follow, lens) riding the layer above it.
final class LinkPreviewCardView: NSView {
  var theme: Theme? {
    didSet { needsDisplay = true }
  }
  var snapshot: NSImage? {
    didSet {
      needsDisplay = true
      refreshLens()
    }
  }
  var failed = false {
    didSet { needsDisplay = true }
  }
  var onClick: (() -> Void)?
  var onHoverChange: ((Bool) -> Void)?

  private var lensTracking: NSTrackingArea?
  private let zoomLayer = CALayer()
  private let lensMask = CAShapeLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    zoomLayer.opacity = 0
    zoomLayer.mask = lensMask
  }

  required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

  private var imageRect: NSRect { LinkPreviewMetrics.imageRect(in: bounds) }

  override func draw(_ dirtyRect: NSRect) {
    guard let theme else { return }
    LinkPreviewChrome.draw(bounds: bounds, theme: theme, snapshot: snapshot, failed: failed)
  }

  // MARK: Lens (magnifier over the open card)

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let lensTracking { removeTrackingArea(lensTracking) }
    let area = NSTrackingArea(
      rect: LinkPreviewMetrics.cardRect(in: bounds),
      options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    lensTracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    onHoverChange?(true)
    guard snapshot != nil else { return }
    installZoomLayerIfNeeded()
    animateLens(visible: true)
  }

  override func mouseExited(with event: NSEvent) {
    onHoverChange?(false)
    animateLens(visible: false)
  }

  override func mouseMoved(with event: NSEvent) {
    guard snapshot != nil, zoomLayer.superlayer != nil else { return }
    positionLens(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseDown(with event: NSEvent) {
    onClick?()
  }

  private func installZoomLayerIfNeeded() {
    guard zoomLayer.superlayer == nil, let layer else { return }
    zoomLayer.frame = imageRect
    zoomLayer.cornerRadius = LinkPreviewMetrics.innerRadius
    zoomLayer.masksToBounds = true
    layer.addSublayer(zoomLayer)
    refreshLens()
  }

  private func refreshLens() {
    guard let snapshot else { return }
    var rect = NSRect(origin: .zero, size: snapshot.size)
    zoomLayer.contents = snapshot.cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }

  private func positionLens(at point: NSPoint) {
    let local = NSPoint(x: point.x - imageRect.minX, y: point.y - imageRect.minY)
    let radius = LinkPreviewMetrics.lensDiameter / 2
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lensMask.path = CGPath(
      ellipseIn: CGRect(
        x: local.x - radius,
        y: local.y - radius,
        width: radius * 2,
        height: radius * 2
      ),
      transform: nil
    )
    zoomLayer.anchorPoint = CGPoint(
      x: local.x / imageRect.width,
      y: local.y / imageRect.height
    )
    zoomLayer.position = CGPoint(
      x: imageRect.minX + local.x,
      y: imageRect.minY + local.y
    )
    zoomLayer.transform = CATransform3DMakeScale(
      LinkPreviewMetrics.lensZoom,
      LinkPreviewMetrics.lensZoom,
      1
    )
    CATransaction.commit()
  }

  private func animateLens(visible: Bool) {
    // Component variants: opacity+scale 0.7->1, 0.2s easeOut in / easeIn out.
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = zoomLayer.presentation()?.opacity ?? zoomLayer.opacity
    fade.toValue = visible ? 1 : 0
    fade.duration = 0.2
    fade.timingFunction = CAMediaTimingFunction(name: visible ? .easeOut : .easeIn)
    zoomLayer.opacity = visible ? 1 : 0
    zoomLayer.add(fade, forKey: "lens-fade")
  }

  // #lizard forgives -- lizard double-records Swift `init`, emitting a
  // phantom function spanning to this brace (LineNumberRuler shows the
  // same artifact); every real member above is within thresholds.
}
