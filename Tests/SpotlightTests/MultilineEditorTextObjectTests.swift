import AppKit
import Testing

@testable import Spotlight

@Suite("Multiline editor Vim text objects")
@MainActor
struct MultilineEditorTextObjectTests {
  @Test("ciw deletes the word under the caret and leaves insert point at the word start")
  func changeInnerWordDeletesWord() {
    let textView = makeTextView(text: "alpha beta gamma")
    textView.setSelectedRange(NSRange(location: ("alpha be" as NSString).length, length: 0))

    textView.executeVimAction(.changeTextObject(.innerWord))

    #expect(textView.string == "alpha  gamma")
    #expect(textView.selectedRange == NSRange(location: ("alpha " as NSString).length, length: 0))
  }

  @Test("caw deletes the word under the caret and one adjacent space")
  func changeAroundWordDeletesWordAndSpace() {
    let textView = makeTextView(text: "alpha beta gamma")
    textView.setSelectedRange(NSRange(location: ("alpha be" as NSString).length, length: 0))

    textView.executeVimAction(.changeTextObject(.aroundWord))

    #expect(textView.string == "alpha gamma")
    #expect(textView.selectedRange == NSRange(location: ("alpha " as NSString).length, length: 0))
  }

  @Test("cis deletes the sentence under the caret without adjacent spaces")
  func changeInnerSentenceDeletesSentence() {
    let textView = makeTextView(text: "First sentence. Second one! Third?")
    textView.setSelectedRange(
      NSRange(location: ("First sentence. Sec" as NSString).length, length: 0)
    )

    textView.executeVimAction(.changeTextObject(.innerSentence))

    #expect(textView.string == "First sentence.  Third?")
    #expect(
      textView.selectedRange
        == NSRange(location: ("First sentence. " as NSString).length, length: 0)
    )
  }

  @Test("cas deletes the sentence under the caret and one adjacent space")
  func changeAroundSentenceDeletesSentenceAndSpace() {
    let textView = makeTextView(text: "First sentence. Second one! Third?")
    textView.setSelectedRange(
      NSRange(location: ("First sentence. Sec" as NSString).length, length: 0)
    )

    textView.executeVimAction(.changeTextObject(.aroundSentence))

    #expect(textView.string == "First sentence. Third?")
    #expect(
      textView.selectedRange
        == NSRange(location: ("First sentence. " as NSString).length, length: 0)
    )
  }

  @Test("cis treats URL dots as part of the current sentence")
  func changeInnerSentenceKeepsUrlDotsInSentence() {
    let textView = makeTextView(text: "Visit example.com now. Next.")
    textView.setSelectedRange(NSRange(location: ("Visit example.c" as NSString).length, length: 0))

    textView.executeVimAction(.changeTextObject(.innerSentence))

    #expect(textView.string == " Next.")
    #expect(textView.selectedRange == NSRange(location: 0, length: 0))
  }

  @Test("cis on the first punctuation-free todo line changes only that line")
  func changeInnerSentenceFallsBackToFirstLogicalLine() {
    let textView = makeTextView(text: "Buy eight sleep\nScan prenup and send")
    textView.setSelectedRange(NSRange(location: ("Buy eight" as NSString).length, length: 0))

    textView.executeVimAction(.changeTextObject(.innerSentence))

    #expect(textView.string == "\nScan prenup and send")
    #expect(textView.selectedRange == NSRange(location: 0, length: 0))
  }

  @Test("cis on the second punctuation-free todo line changes only that line")
  func changeInnerSentenceFallsBackToSecondLogicalLine() {
    let textView = makeTextView(text: "Buy eight sleep\nScan prenup and send")
    let secondLineLocation = ("Buy eight sleep\nScan" as NSString).length
    textView.setSelectedRange(NSRange(location: secondLineLocation, length: 0))

    textView.executeVimAction(.changeTextObject(.innerSentence))

    #expect(textView.string == "Buy eight sleep\n")
    #expect(
      textView.selectedRange
        == NSRange(location: ("Buy eight sleep\n" as NSString).length, length: 0)
    )
  }

  @Test("cis on adjacent punctuation-free list items changes only the current item")
  func changeInnerSentenceFallsBackToCurrentListItem() {
    let textView = makeTextView(text: "- Buy eight sleep\n- Scan prenup and send")
    let secondLineLocation = ("- Buy eight sleep\n- Scan" as NSString).length
    textView.setSelectedRange(NSRange(location: secondLineLocation, length: 0))

    textView.executeVimAction(.changeTextObject(.innerSentence))

    #expect(textView.string == "- Buy eight sleep\n")
    #expect(
      textView.selectedRange
        == NSRange(location: ("- Buy eight sleep\n" as NSString).length, length: 0)
    )
  }

  @Test("cis on closing quote targets the quoted sentence")
  func changeInnerSentenceAtClosingQuoteTargetsQuotedSentence() {
    let textView = makeTextView(text: "\"First.\" Second.")
    textView.setSelectedRange(NSRange(location: ("\"First." as NSString).length, length: 0))

    textView.executeVimAction(.changeTextObject(.innerSentence))

    #expect(textView.string == " Second.")
    #expect(textView.selectedRange == NSRange(location: 0, length: 0))
  }

  @Test("dip deletes indented paragraph text including edge spaces")
  func deleteInnerParagraphKeepsSeparatorsOnly() {
    let textView = makeTextView(text: "Alpha.\n\n  Beta line.  \n\nGamma.")
    textView.setSelectedRange(NSRange(location: ("Alpha.\n\n  Beta" as NSString).length, length: 0))

    textView.executeVimAction(.deleteTextObject(.innerParagraph))

    #expect(textView.string == "Alpha.\n\n\n\nGamma.")
    #expect(
      textView.selectedRange == NSRange(location: ("Alpha.\n\n" as NSString).length, length: 0)
    )
  }

  @Test("dap deletes the current paragraph plus its following separator")
  func deleteAroundParagraphDeletesParagraphAndSeparator() {
    let textView = makeTextView(text: "Alpha one.\n\nBeta line one.\nBeta line two.\n\nGamma.")
    textView.setSelectedRange(
      NSRange(location: ("Alpha one.\n\nBeta line" as NSString).length, length: 0)
    )

    textView.executeVimAction(.deleteTextObject(.aroundParagraph))

    #expect(textView.string == "Alpha one.\n\nGamma.")
    #expect(
      textView.selectedRange == NSRange(location: ("Alpha one.\n\n" as NSString).length, length: 0)
    )
  }

  @Test("dap includes a trailing-space paragraph before its separator")
  func deleteAroundParagraphIncludesTrailingSpaceBeforeSeparator() {
    let textView = makeTextView(text: "Alpha one.\n\nBeta line.   \n\nGamma.")
    textView.setSelectedRange(
      NSRange(location: ("Alpha one.\n\nBeta line" as NSString).length, length: 0)
    )

    textView.executeVimAction(.deleteTextObject(.aroundParagraph))

    #expect(textView.string == "Alpha one.\n\nGamma.")
    #expect(
      textView.selectedRange == NSRange(location: ("Alpha one.\n\n" as NSString).length, length: 0)
    )
  }

  private func makeTextView(
    text: String,
    width: CGFloat = EditorMetrics.panelWidth,
    theme: Theme = ThemeCatalog.obsidian
  ) -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: width, height: 240))
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text
    textView.textColor = NSColor(theme.text)
    textView.editorTheme = theme
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.editorTextAttributes = [
      .font: textView.font ?? NSFont.systemFont(ofSize: EditorMetrics.fontSize),
      .foregroundColor: NSColor(theme.text)
    ]
    textView.typingAttributes = textView.editorTextAttributes
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
    CodeStyler.apply(to: textView, theme: theme)
    return textView
  }
}
