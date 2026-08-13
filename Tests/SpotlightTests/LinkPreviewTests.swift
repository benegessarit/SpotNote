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

  @Test("styling never adds temporary attributes inside a storage edit session")
  func noTemporaryAttributesMidEdit() throws {
    // makeNSView launch-crash regression: a temporary-attribute add
    // between beginEditing/endEditing makes AppKit fill glyph holes
    // mid-edit and raise (the display-invalidation path only fires with
    // a visible window, so the raise itself cannot reproduce headless
    // -- audit the forbidden call pattern directly instead).
    let storage = EditingDepthTextStorage()
    storage.replaceCharacters(
      in: NSRange(location: 0, length: 0),
      with: "note https://godui.design/docs end"
    )
    let layoutManager = TemporaryAttributeAuditLayoutManager()
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: 600, height: 240))
    layoutManager.addTextContainer(container)
    let textView = PlaceholderTextView(
      frame: NSRect(x: 0, y: 0, width: 600, height: 240),
      textContainer: container
    )
    textView.font = SpotNoteFont.editor()
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    CodeStyler.apply(to: textView, theme: ThemeCatalog.mirage)
    #expect(layoutManager.midEditTemporaryAttributeAdds == 0)
    let span = try #require(textView.linkSpans.first)
    #expect(temporaryForegroundColor(at: span.visibleRange.location, in: textView) != nil)
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

/// Text storage that exposes its `beginEditing` nesting depth so the
/// audit layout manager can detect the forbidden mid-edit pattern.
private final class EditingDepthTextStorage: NSTextStorage {
  private let backing = NSMutableAttributedString()
  private(set) var editingDepth = 0

  override var string: String { backing.string }

  override func attributes(
    at location: Int,
    effectiveRange range: NSRangePointer?
  ) -> [NSAttributedString.Key: Any] {
    backing.attributes(at: location, effectiveRange: range)
  }

  override func replaceCharacters(in range: NSRange, with str: String) {
    backing.replaceCharacters(in: range, with: str)
    edited(
      .editedCharacters,
      range: range,
      changeInLength: (str as NSString).length - range.length
    )
  }

  override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
    backing.setAttributes(attrs, range: range)
    edited(.editedAttributes, range: range, changeInLength: 0)
  }

  override func beginEditing() {
    editingDepth += 1
    super.beginEditing()
  }

  override func endEditing() {
    editingDepth -= 1
    super.endEditing()
  }
}

/// Layout manager that counts temporary-attribute adds arriving while
/// its storage is mid-edit -- the pattern that raises (and crashed the
/// app) whenever display invalidation must generate glyphs.
private final class TemporaryAttributeAuditLayoutManager: NSLayoutManager {
  private(set) var midEditTemporaryAttributeAdds = 0

  private func auditEditingDepth() {
    if (textStorage as? EditingDepthTextStorage)?.editingDepth ?? 0 > 0 {
      midEditTemporaryAttributeAdds += 1
    }
  }

  override func addTemporaryAttribute(
    _ attrName: NSAttributedString.Key,
    value: Any,
    forCharacterRange charRange: NSRange
  ) {
    auditEditingDepth()
    super.addTemporaryAttribute(attrName, value: value, forCharacterRange: charRange)
  }

  override func addTemporaryAttributes(
    _ attrs: [NSAttributedString.Key: Any],
    forCharacterRange charRange: NSRange
  ) {
    auditEditingDepth()
    super.addTemporaryAttributes(attrs, forCharacterRange: charRange)
  }
}
