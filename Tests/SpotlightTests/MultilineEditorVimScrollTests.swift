import AppKit
import Testing

@testable import Spotlight

@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  @Test("j scrolls the viewport down when the next logical line leaves the visible note")
  func downScrollsViewportWithCaret() {
    let text = (0..<20).map { "line \($0)" }.joined(separator: "\n")
    let textView = makeScrollableVimMotionTextView(text: text)
    let scrollView = makeScrollView(containing: textView)
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    scrollView.contentView.scroll(to: .zero)
    scrollView.reflectScrolledClipView(scrollView.contentView)

    textView.executeMotion(.down(5))

    #expect(textView.selectedRange.location == lineStart(5, in: text))
    #expect(abs(scrollView.contentView.documentVisibleRect.minY - EditorMetrics.lineHeight) < 0.001)
  }

  @Test("k scrolls the viewport up when the previous logical line leaves the visible note")
  func upScrollsViewportWithCaret() {
    let text = (0..<20).map { "line \($0)" }.joined(separator: "\n")
    let textView = makeScrollableVimMotionTextView(text: text)
    let scrollView = makeScrollView(containing: textView)
    let startingY = EditorMetrics.lineHeight * 12
    textView.setSelectedRange(NSRange(location: lineStart(12, in: text), length: 0))
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: startingY))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    textView.executeMotion(.up(1))

    #expect(textView.selectedRange.location == lineStart(11, in: text))
    #expect(abs(scrollView.contentView.documentVisibleRect.minY - EditorMetrics.lineHeight * 11) < 0.001)
  }
}
