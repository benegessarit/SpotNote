import AppKit

final class SpotNoteScrollView: NSScrollView {
  override func tile() {
    super.tile()
    SpotNoteScrollViewStyle.reserveDocumentLane(in: self)
  }
}

enum SpotNoteScrollViewStyle {
  static let reservedVerticalLaneWidth: CGFloat = 10

  static func stableDocumentWidth(for contentWidth: CGFloat) -> CGFloat {
    max(0, contentWidth - reservedVerticalLaneWidth)
  }

  @MainActor
  static func apply(to scroll: NSScrollView) {
    scroll.drawsBackground = false
    scroll.borderType = .noBorder
    scroll.hasVerticalScroller = true
    scroll.verticalScroller = SpotNoteScroller()
    scroll.scrollerStyle = .overlay
    scroll.scrollerKnobStyle = .dark
    scroll.automaticallyAdjustsContentInsets = false
    scroll.contentInsets = NSEdgeInsetsZero
    scroll.scrollerInsets = NSEdgeInsetsZero
    scroll.autohidesScrollers = false
    scroll.hasHorizontalScroller = false
    scroll.wantsLayer = true
    scroll.layer?.masksToBounds = true
    reserveDocumentLane(in: scroll)
  }

  @MainActor
  static func reserveDocumentLane(in scroll: NSScrollView) {
    guard let documentView = scroll.documentView else { return }
    let stableWidth = stableDocumentWidth(for: scroll.contentView.bounds.width)
    guard stableWidth > 0 else { return }
    if abs(documentView.frame.width - stableWidth) > 0.5 {
      documentView.setFrameSize(NSSize(width: stableWidth, height: documentView.frame.height))
    }
  }
}

final class SpotNoteScroller: NSScroller {
  private static let trackWidth: CGFloat = 2
  private static let thumbWidth: CGFloat = 5
  static let thumbTrailingInset: CGFloat = 1.5
  private static let verticalInset: CGFloat = 2

  override static var isCompatibleWithOverlayScrollers: Bool { true }

  override static func scrollerWidth(
    for controlSize: NSControl.ControlSize,
    scrollerStyle: NSScroller.Style
  ) -> CGFloat {
    SpotNoteScrollViewStyle.reservedVerticalLaneWidth
  }

  override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
    guard flag else { return }
    let track = centeredRect(width: Self.trackWidth, in: slotRect).insetBy(dx: 0, dy: 4)
    NSColor(white: 1, alpha: 0.08).setFill()
    NSBezierPath(
      roundedRect: track,
      xRadius: Self.trackWidth / 2,
      yRadius: Self.trackWidth / 2
    ).fill()
  }

  override func drawKnob() {
    let knob = rect(for: .knob)
    guard !knob.isEmpty else { return }
    let thumb = NSRect(
      x: knob.maxX - Self.thumbTrailingInset - Self.thumbWidth,
      y: knob.minY + Self.verticalInset,
      width: Self.thumbWidth,
      height: max(Self.thumbWidth * 2, knob.height - Self.verticalInset * 2)
    )
    let alpha: CGFloat = isHighlighted ? 0.68 : 0.46
    NSColor(white: 0.72, alpha: alpha).setFill()
    NSBezierPath(
      roundedRect: thumb,
      xRadius: Self.thumbWidth / 2,
      yRadius: Self.thumbWidth / 2
    ).fill()
  }

  private func centeredRect(width: CGFloat, in rect: NSRect) -> NSRect {
    NSRect(
      x: rect.maxX - Self.thumbTrailingInset - Self.thumbWidth / 2 - width / 2,
      y: rect.minY,
      width: width,
      height: rect.height
    )
  }
}
