import AppKit

/// Hover plumbing for pasted-link previews: hit-testing the concealed
/// spans under the mouse, anchoring the HoverPeek card above the link,
/// feeding the mouse-follow offset, and revealing the full URL while the
/// caret touches it. Spans are cached on the view by `CodeStylerLinks`;
/// the card itself lives in LinkPreviewPanel.swift.
extension PlaceholderTextView {
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    refreshLinkHoverTracking()
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    handleLinkHoverMove(event)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    handleLinkHoverExit()
  }

  override func mouseDown(with event: NSEvent) {
    if handleLinkMouseDown(event) { return }
    super.mouseDown(with: event)
  }

  func refreshLinkHoverTracking() {
    if let area = linkTrackingArea {
      removeTrackingArea(area)
    }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    linkTrackingArea = area
  }

  func handleLinkHoverMove(_ event: NSEvent) {
    guard let window, let theme = editorTheme, !linkSpans.isEmpty else {
      linkPreview.scheduleClose()
      return
    }
    let point = convert(event.locationInWindow, from: nil)
    guard let span = linkSpan(at: point), let anchor = linkAnchorRect(for: span) else {
      linkPreview.scheduleClose()
      return
    }
    let screenRect = window.convertToScreen(convert(anchor, to: nil))
    linkPreview.scheduleOpen(
      url: span.url,
      anchorScreenRect: screenRect,
      parent: window,
      theme: theme
    )
    linkPreview.follow(offsetX: point.x - anchor.midX)
  }

  func handleLinkHoverExit() {
    linkPreview.scheduleClose()
  }

  /// Cmd-click opens the link (standard macOS text affordance); returns
  /// true when consumed so the caller skips caret placement.
  func handleLinkMouseDown(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.command) else { return false }
    let point = convert(event.locationInWindow, from: nil)
    guard let span = linkSpan(at: point) else { return false }
    NSWorkspace.shared.open(span.url)
    return true
  }

  /// True when the caret moved onto or off a link, so the styler pass can
  /// re-run once per transition (never per keystroke of ordinary motion --
  /// the full-document restyle is the typing hot path's cost ceiling).
  func linkRevealStateChanged() -> Bool {
    let revealed = linkSpans.first { CodeStylerLinks.touches(selectedRange, $0.range) }?.range
    guard revealed != linkRevealCache else { return false }
    linkRevealCache = revealed
    return true
  }

  private func linkSpan(at point: NSPoint) -> LinkSpan? {
    guard let layoutManager, let textContainer else { return nil }
    let containerPoint = NSPoint(
      x: point.x - textContainerOrigin.x,
      y: point.y - textContainerOrigin.y
    )
    let index = layoutManager.characterIndex(
      for: containerPoint,
      in: textContainer,
      fractionOfDistanceBetweenInsertionPoints: nil
    )
    guard let span = LinkDetection.span(at: index, in: linkSpans) else { return nil }
    // `characterIndex(for:)` snaps to the NEAREST character, so a point in
    // the empty margin past a line still lands in the span -- require the
    // pointer to actually sit on the link's ink.
    guard let anchor = linkAnchorRect(for: span),
      anchor.insetBy(dx: -2, dy: -2).contains(point)
    else { return nil }
    return span
  }

  private func linkAnchorRect(for span: LinkSpan) -> NSRect? {
    guard let layoutManager, let textContainer else { return nil }
    let glyphs = layoutManager.glyphRange(forCharacterRange: span.range, actualCharacterRange: nil)
    guard glyphs.length > 0 else { return nil }
    var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
    rect.origin.x += textContainerOrigin.x
    rect.origin.y += textContainerOrigin.y
    return rect
  }
}
