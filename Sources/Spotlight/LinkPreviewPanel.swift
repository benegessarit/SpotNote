import AppKit

/// Owns the floating preview panel: a borderless nonactivating child of
/// the editor's window (the `RaycastModalChildPanel` presentation idiom,
/// minus key status -- hover chrome must never steal focus). Presents the
/// card with the component's spring flip-in, tracks the 0.3-gain mouse
/// follow, and arbitrates the open/close delays between link and card.
@MainActor
final class LinkPreviewController {
  private var panel: NSPanel?
  private var cardView: LinkPreviewCardView?
  private var openTimer: Timer?
  private var closeTimer: Timer?
  private var followBaseX: CGFloat = 0
  private var activeURL: URL?
  private var mouseInsideCard = false

  /// Schedules the card after the component's 75ms open delay.
  func scheduleOpen(
    url: URL,
    anchorScreenRect: NSRect,
    parent: NSWindow,
    theme: Theme
  ) {
    closeTimer?.invalidate()
    closeTimer = nil
    guard url != activeURL || panel == nil else { return }
    openTimer?.invalidate()
    openTimer = Timer.scheduledTimer(
      withTimeInterval: LinkPreviewMetrics.openDelay,
      repeats: false
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.present(url: url, anchorScreenRect: anchorScreenRect, parent: parent, theme: theme)
      }
    }
  }

  /// Schedules dismissal after the 150ms close delay; hovering the card
  /// (or re-entering the link) cancels it.
  func scheduleClose() {
    openTimer?.invalidate()
    openTimer = nil
    guard panel != nil, closeTimer == nil else { return }
    closeTimer = Timer.scheduledTimer(
      withTimeInterval: LinkPreviewMetrics.closeDelay,
      repeats: false
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, !self.mouseInsideCard else { return }
        self.dismiss()
      }
    }
  }

  /// Mouse-follow x from the trigger link: offset scaled by the 0.3 gain,
  /// sprung at the component's 120/20 spring.
  func follow(offsetX: CGFloat) {
    guard let cardView, let layer = cardView.layer else { return }
    let target = followBaseX + offsetX * LinkPreviewMetrics.followGain
    let spring = CASpringAnimation(keyPath: "position.x")
    spring.stiffness = 120
    spring.damping = 20
    spring.mass = 1
    spring.fromValue = layer.presentation()?.position.x ?? layer.position.x
    spring.toValue = target
    spring.duration = spring.settlingDuration
    layer.position.x = target
    layer.add(spring, forKey: "follow")
  }

  func dismiss() {
    openTimer?.invalidate()
    openTimer = nil
    closeTimer?.invalidate()
    closeTimer = nil
    mouseInsideCard = false
    activeURL = nil
    guard let panel else { return }
    panel.parent?.removeChildWindow(panel)
    panel.orderOut(nil)
    self.panel = nil
    cardView = nil
  }

  private func present(url: URL, anchorScreenRect: NSRect, parent: NSWindow, theme: Theme) {
    dismiss()
    activeURL = url
    let containerSize = LinkPreviewMetrics.containerSize
    let card = makeCardView(url: url, theme: theme)
    let container = makePerspectiveContainer(hosting: card)
    let panel = makePanel(parent: parent, contentView: container)
    let origin = NSPoint(
      x: anchorScreenRect.midX - containerSize.width / 2,
      y: anchorScreenRect.maxY + LinkPreviewMetrics.sideOffset
        - (containerSize.height - LinkPreviewMetrics.cardSize.height) / 2
    )
    panel.setFrame(NSRect(origin: origin, size: containerSize), display: true)
    parent.addChildWindow(panel, ordered: .above)
    self.panel = panel
    cardView = card
    followBaseX = card.layer?.position.x ?? containerSize.width / 2
    animateFlipIn(card)
    LinkSnapshotter.shared.snapshot(url, darkAppearance: theme.mode == .dark) { [weak self] image in
      guard let self, self.activeURL == url, let cardView = self.cardView else { return }
      if let image {
        cardView.snapshot = image
      } else {
        cardView.failed = true
      }
    }
  }

  private func makeCardView(url: URL, theme: Theme) -> LinkPreviewCardView {
    let card = LinkPreviewCardView(
      frame: NSRect(origin: .zero, size: LinkPreviewMetrics.containerSize)
    )
    card.theme = theme
    card.onClick = { NSWorkspace.shared.open(url) }
    card.onHoverChange = { [weak self] inside in
      self?.mouseInsideCard = inside
      if inside {
        self?.closeTimer?.invalidate()
        self?.closeTimer = nil
      } else {
        self?.scheduleClose()
      }
    }
    return card
  }

  /// The card's superlayer carries the 800px perspective (framer's
  /// `[perspective:800px]` container) so the rotation.y flip reads as a
  /// 3D card turn. macOS view layers anchor at (0,0); re-anchor the card
  /// to its center so the flip and follow both act about the middle.
  private func makePerspectiveContainer(hosting card: LinkPreviewCardView) -> NSView {
    let container = NSView(
      frame: NSRect(origin: .zero, size: LinkPreviewMetrics.containerSize)
    )
    container.wantsLayer = true
    var perspective = CATransform3DIdentity
    perspective.m34 = -1 / LinkPreviewMetrics.perspective
    container.layer?.sublayerTransform = perspective
    container.addSubview(card)
    if let layer = card.layer {
      layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
      layer.position = CGPoint(
        x: container.bounds.midX,
        y: container.bounds.midY
      )
    }
    return container
  }

  private func makePanel(parent: NSWindow, contentView: NSView) -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: LinkPreviewMetrics.containerSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    // The card draws its own Tailwind shadow stack; the window-server
    // shadow's hard contact rim is exactly what RaycastModalChildPanel
    // disables for the same reason.
    panel.hasShadow = false
    panel.level = parent.level
    panel.isReleasedWhenClosed = false
    panel.contentView = contentView
    return panel
  }

  private func animateFlipIn(_ card: LinkPreviewCardView) {
    guard let layer = card.layer else { return }
    let flip = CASpringAnimation(keyPath: "transform.rotation.y")
    flip.stiffness = 200
    flip.damping = 18
    flip.mass = 1
    flip.fromValue = -CGFloat.pi / 2
    flip.toValue = 0
    flip.duration = flip.settlingDuration
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = 0.15
    layer.add(flip, forKey: "flip-in")
    layer.add(fade, forKey: "fade-in")
  }
}
