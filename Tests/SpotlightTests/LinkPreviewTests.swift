import AppKit
import Testing

@testable import Spotlight

@Suite("Pasted-link detection and conceal geometry")
struct LinkDetectionTests {
  @Test("an http(s) URL yields scheme + path conceal around a visible host")
  func spanGeometry() throws {
    let text = "see https://godui.design/docs/components?x=1 now"
    let spans = LinkDetection.spans(in: text)
    let span = try #require(spans.first)
    #expect(spans.count == 1)
    let nsText = text as NSString
    #expect(nsText.substring(with: span.leadingConceal) == "https://")
    #expect(nsText.substring(with: span.visibleRange) == "godui.design")
    #expect(nsText.substring(with: span.trailingConceal) == "/docs/components?x=1")
    #expect(span.url.host == "godui.design")
  }

  @Test("host-only URLs conceal just the scheme")
  func hostOnly() throws {
    let spans = LinkDetection.spans(in: "https://example.com")
    let span = try #require(spans.first)
    #expect(span.trailingConceal.length == 0)
    #expect(span.visibleRange.length == "example.com".count)
  }

  @Test("bare domains and non-web schemes are ignored")
  func ignoresNonWebLinks() {
    #expect(LinkDetection.spans(in: "see example.com and mailto:a@b.com").isEmpty)
    #expect(LinkDetection.spans(in: "no links at all").isEmpty)
  }

  @Test("caret touching either end of a link counts as inside")
  func caretTouch() throws {
    let text = "x https://a.io y"
    let span = try #require(LinkDetection.spans(in: text).first)
    #expect(LinkDetection.span(touching: span.range.location, in: [span]) != nil)
    #expect(LinkDetection.span(touching: NSMaxRange(span.range), in: [span]) != nil)
    #expect(LinkDetection.span(touching: 0, in: [span]) == nil)
    // Half-open hover hit-test excludes the trailing boundary.
    #expect(LinkDetection.span(at: NSMaxRange(span.range), in: [span]) == nil)
  }
}

@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  @Test("styling conceals scheme+path to hairline and reveals while the caret touches")
  func concealAndCaretReveal() throws {
    let text = "note https://godui.design/docs end"
    let textView = makeVimMotionTextView(text: text)
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    CodeStyler.apply(to: textView, theme: ThemeCatalog.mirage)

    let span = try #require(textView.linkSpans.first)
    let storage = try #require(textView.textStorage)
    let schemeFont = storage.attribute(.font, at: span.leadingConceal.location, effectiveRange: nil)
    #expect((schemeFont as? NSFont)?.pointSize == CodeStylerLinks.concealFont.pointSize)
    let hostFont = storage.attribute(.font, at: span.visibleRange.location, effectiveRange: nil)
    #expect((hostFont as? NSFont)?.pointSize == SpotNoteFont.editor().pointSize)

    // Caret onto the link -> the transition flags a restyle, and the
    // conceal opens back to the full URL at body size.
    textView.setSelectedRange(NSRange(location: span.range.location + 2, length: 0))
    #expect(textView.linkRevealStateChanged() == true)
    #expect(textView.linkRevealStateChanged() == false)
    CodeStyler.apply(to: textView, theme: ThemeCatalog.mirage)
    let revealedFont = storage.attribute(
      .font,
      at: span.leadingConceal.location,
      effectiveRange: nil
    )
    #expect((revealedFont as? NSFont)?.pointSize == SpotNoteFont.editor().pointSize)

    // Caret back out -> transition flags again, restyle re-conceals.
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    #expect(textView.linkRevealStateChanged() == true)
    CodeStyler.apply(to: textView, theme: ThemeCatalog.mirage)
    let concealedAgain = storage.attribute(
      .font,
      at: span.leadingConceal.location,
      effectiveRange: nil
    )
    #expect((concealedAgain as? NSFont)?.pointSize == CodeStylerLinks.concealFont.pointSize)
    #expect(textView.string == text)
  }

  @Test("deleting the link clears spans and leaves no conceal fonts behind")
  func deletedLinkUnconceals() throws {
    let textView = makeVimMotionTextView(text: "a https://x.io b")
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    CodeStyler.apply(to: textView, theme: ThemeCatalog.mirage)
    #expect(!textView.linkSpans.isEmpty)
    textView.string = "a plain b"
    CodeStyler.apply(to: textView, theme: ThemeCatalog.mirage)
    #expect(textView.linkSpans.isEmpty)
    let storage = try #require(textView.textStorage)
    var sawConceal = false
    storage.enumerateAttribute(
      .font,
      in: NSRange(location: 0, length: storage.length)
    ) { value, _, _ in
      if (value as? NSFont)?.pointSize == CodeStylerLinks.concealFont.pointSize {
        sawConceal = true
      }
    }
    #expect(sawConceal == false)
  }
}

@MainActor
@Suite("Link preview card chrome")
struct LinkPreviewCardTests {
  @Test("HoverPeek geometry: 200x125 well in a 2px frame with 1px border")
  func metrics() {
    #expect(LinkPreviewMetrics.cardSize == NSSize(width: 206, height: 131))
    let bounds = NSRect(origin: .zero, size: LinkPreviewMetrics.containerSize)
    let card = LinkPreviewMetrics.cardRect(in: bounds)
    #expect(card.width == 206)
    #expect(LinkPreviewMetrics.imageRect(in: bounds).size == LinkPreviewMetrics.imageSize)
  }

  /// Renders the card chrome offscreen at 2x -- the deterministic probe
  /// the pixel-goal loop diffs against the themed HoverPeek reference.
  /// Set SPOTNOTE_CARD_CAPTURE_PATH to write the PNG for the loop.
  @Test("chrome renders at 2x with the theme frame and well colors")
  func chromeProbeRender() throws {
    let size = LinkPreviewMetrics.containerSize
    let rep = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * 2,
        pixelsHigh: Int(size.height) * 2,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let theme = ThemeCatalog.mirage
    NSColor(theme.background).setFill()
    NSRect(origin: .zero, size: size).fill()
    LinkPreviewChrome.draw(
      bounds: NSRect(origin: .zero, size: size),
      theme: theme,
      snapshot: nil,
      failed: false
    )
    NSGraphicsContext.restoreGraphicsState()

    let center = try #require(rep.colorAt(x: 280, y: 200)?.usingColorSpace(.sRGB))
    let well = try #require(
      LinkPreviewPalette.well(for: theme).usingColorSpace(.sRGB)
    )
    #expect(abs(center.redComponent - well.redComponent) < 0.02)
    #expect(abs(center.blueComponent - well.blueComponent) < 0.02)

    let capturePath = ProcessInfo.processInfo.environment["SPOTNOTE_CARD_CAPTURE_PATH"]
    if let capturePath, let png = rep.representation(using: .png, properties: [:]) {
      try png.write(to: URL(fileURLWithPath: capturePath))
    }
  }
}
