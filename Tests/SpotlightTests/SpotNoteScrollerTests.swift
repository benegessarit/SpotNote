import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("SpotNote scroller styling")
struct SpotNoteScrollerTests {
  @Test("scroll view style uses the minimal overlay scroller and hides it at rest")
  func scrollViewStyleUsesMinimalOverlayScrollerAndHidesAtRest() {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

    SpotNoteScrollViewStyle.apply(to: scrollView)

    #expect(scrollView.verticalScroller is SpotNoteScroller)
    #expect(scrollView.hasVerticalScroller)
    #expect(scrollView.scrollerStyle == .overlay)
    #expect(scrollView.autohidesScrollers)
    #expect(!scrollView.automaticallyAdjustsContentInsets)
    #expect(scrollView.contentInsets.top == 0)
    #expect(scrollView.contentInsets.left == 0)
    #expect(scrollView.contentInsets.bottom == 0)
    #expect(scrollView.contentInsets.right == 0)
    #expect(SpotNoteScrollViewStyle.reservedVerticalLaneWidth <= 10)
    #expect(SpotNoteScroller.thumbTrailingInset <= 1.5)
    #expect(SpotNoteScroller.normalThumbAlpha <= 0.28)
    #expect(SpotNoteScroller.highlightedThumbAlpha <= 0.44)
    #expect(SpotNoteScroller.highlightTrackAlpha <= 0.05)
    #expect(!scrollView.hasHorizontalScroller)
    #expect(
      SpotNoteScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)
        < NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    )
  }

  @Test("scrollbar lane is reserved by stable document width, not visibility")
  func scrollbarLaneIsReservedByStableDocumentWidth() {
    let scrollView = SpotNoteScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    SpotNoteScrollViewStyle.apply(to: scrollView)
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    scrollView.documentView = textView

    scrollView.tile()
    let firstWidth = textView.frame.width
    scrollView.verticalScroller?.isHidden.toggle()
    scrollView.tile()

    #expect(firstWidth == scrollView.contentView.bounds.width - SpotNoteScrollViewStyle.reservedVerticalLaneWidth)
    #expect(textView.frame.width == firstWidth)
  }
}
