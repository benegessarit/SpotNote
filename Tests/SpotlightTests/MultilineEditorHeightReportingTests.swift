import AppKit
import SwiftUI
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor height reporting")
struct MultilineEditorHeightReportingTests {
  @Test("typing past the visible-line cap does not re-report an unchanged height")
  func typingPastVisibleLineCapDoesNotReemitUnchangedHeight() {
    let initialText = (0..<4).map { "line \($0)" }.joined(separator: "\n")
    var boundText = initialText
    var heights: [CGFloat] = []
    let parent = MultilineEditor(
      text: Binding(
        get: { boundText },
        set: { boundText = $0 }
      ),
      theme: ThemeCatalog.obsidian,
      placeholder: "",
      showLineNumbers: false,
      font: .systemFont(ofSize: EditorMetrics.fontSize),
      focusRequest: 0,
      maxVisibleLines: 4,
      extraChromeHeight: 0,
      onHeightChange: { heights.append($0) }
    )
    let coordinator = MultilineEditor.Coordinator(parent)
    let textView = makeTextView(text: initialText)

    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    insert("\nline 4", into: textView)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

    #expect(boundText == initialText + "\nline 4")
    #expect(heights == [EditorMetrics.panelHeight(forLines: 4, maxLines: 4)])
  }

  private func makeTextView(text: String) -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 200))
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text
    textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.minimumLineHeight = EditorMetrics.lineHeight
    paragraphStyle.maximumLineHeight = EditorMetrics.lineHeight
    textView.defaultParagraphStyle = paragraphStyle
    textView.editorTextAttributes = [
      .font: textView.font ?? NSFont.systemFont(ofSize: EditorMetrics.fontSize),
      .paragraphStyle: paragraphStyle
    ]
    textView.typingAttributes = textView.editorTextAttributes
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    guard let storage = textView.textStorage,
      let container = textView.textContainer
    else { return textView }
    let fixed = FixedLineHeightLayoutManager()
    fixed.fixedLineHeight = EditorMetrics.lineHeight
    fixed.editorFont = textView.font ?? .systemFont(ofSize: EditorMetrics.fontSize)
    if let existing = storage.layoutManagers.first {
      storage.removeLayoutManager(existing)
    }
    storage.addLayoutManager(fixed)
    fixed.addTextContainer(container)
    return textView
  }

  private func insert(_ replacement: String, into textView: PlaceholderTextView) {
    let range = textView.selectedRange
    _ = textView.shouldChangeText(in: range, replacementString: replacement)
    let nsString = textView.string as NSString
    textView.string = nsString.replacingCharacters(in: range, with: replacement)
    textView.setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
  }
}
