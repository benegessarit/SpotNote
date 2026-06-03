import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor caret drawing")
struct MultilineEditorCaretTests {
  @Test("normal mode caret display rect uses full block width")
  func normalModeCaretDisplayRectUsesFullBlockWidth() {
    let textView = makeCaretTextView(text: "alpha\nbeta")
    textView.vimModeEnabled = true
    let thinAppKitCaretRect = NSRect(x: 80, y: 22, width: 1, height: EditorMetrics.lineHeight)

    let display = textView.insertionPointDisplayRect(for: thinAppKitCaretRect, turnedOn: true)

    #expect(display.width >= textView.normalModeInsertionPointWidth())
  }

  @Test("normal mode caret invalidation covers the full block cursor")
  func normalModeCaretInvalidationCoversFullBlockCursor() {
    let textView = makeCaretTextView(text: "alpha\nbeta")
    textView.vimModeEnabled = true
    let thinAppKitCaretRect = NSRect(x: 80, y: 22, width: 1, height: EditorMetrics.lineHeight)

    let invalidation = textView.insertionPointInvalidationRect(for: thinAppKitCaretRect)

    #expect(invalidation.minX < thinAppKitCaretRect.minX)
    #expect(invalidation.maxX > thinAppKitCaretRect.maxX)
    #expect(invalidation.width >= textView.normalModeInsertionPointWidth() * 2)
  }

  private func makeCaretTextView(text: String) -> PlaceholderTextView {
    let textView = PlaceholderTextView(
      frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 160)
    )
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text
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
}
