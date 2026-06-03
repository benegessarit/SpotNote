import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor visual character mode")
struct MultilineEditorVisualCharacterTests {
  @Test("v starts characterwise visual selection at the current character")
  func visualCharacterStartsAtCurrentCharacter() {
    let textView = makeVimMotionTextView(text: "Pay Emanuel dues")
    textView.vimModeEnabled = true
    let start = ("Pay " as NSString).length
    textView.setSelectedRange(NSRange(location: start, length: 0))

    textView.keyDown(with: keyEvent(characters: "v", ignoring: "v", keyCode: 9))

    #expect(textView.selectedRange == NSRange(location: start, length: 1))
    #expect((textView.string as NSString).substring(with: textView.selectedRange) == "E")
  }

  @Test("ve selects from the current character through the end of the word")
  func visualCharacterWordEndSelectsThroughWordEnd() {
    let textView = makeVimMotionTextView(text: "Pay Emanuel dues")
    textView.vimModeEnabled = true
    let start = ("Pay " as NSString).length
    textView.setSelectedRange(NSRange(location: start, length: 0))

    textView.keyDown(with: keyEvent(characters: "v", ignoring: "v", keyCode: 9))
    textView.keyDown(with: keyEvent(characters: "e", ignoring: "e", keyCode: 14))

    let expected = NSRange(location: start, length: ("Emanuel" as NSString).length)
    #expect(textView.selectedRange == expected)
    #expect((textView.string as NSString).substring(with: textView.selectedRange) == "Emanuel")
  }

  @Test("visual character change deletes only the selected characters and enters insert")
  func visualCharacterChangeDeletesSelectionAndEntersInsert() {
    let textView = makeVimMotionTextView(text: "Pay Emanuel dues")
    textView.vimModeEnabled = true
    let start = ("Pay " as NSString).length
    textView.setSelectedRange(NSRange(location: start, length: 0))

    textView.keyDown(with: keyEvent(characters: "v", ignoring: "v", keyCode: 9))
    textView.keyDown(with: keyEvent(characters: "e", ignoring: "e", keyCode: 14))
    textView.keyDown(with: keyEvent(characters: "c", ignoring: "c", keyCode: 8))

    #expect(textView.string == "Pay  dues")
    #expect(textView.selectedRange == NSRange(location: start, length: 0))
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("v dollar selects through line end without including the newline")
  func visualCharacterLineEndStopsBeforeNewline() {
    let textView = makeVimMotionTextView(text: "abc\ndef")
    textView.vimModeEnabled = true
    textView.setSelectedRange(NSRange(location: 1, length: 0))

    textView.keyDown(with: keyEvent(characters: "v", ignoring: "v", keyCode: 9))
    textView.keyDown(with: keyEvent(characters: "$", ignoring: "$", keyCode: 21, modifiers: .shift))

    #expect((textView.string as NSString).substring(with: textView.selectedRange) == "bc")
  }

  @Test("de deletes through the current word end")
  func deleteWordEndIncludesLastCharacter() {
    let textView = makeVimMotionTextView(text: "Pay Emanuel dues")
    textView.vimModeEnabled = true
    let start = ("Pay " as NSString).length
    textView.setSelectedRange(NSRange(location: start, length: 0))

    textView.keyDown(with: keyEvent(characters: "d", ignoring: "d", keyCode: 2))
    textView.keyDown(with: keyEvent(characters: "e", ignoring: "e", keyCode: 14))

    #expect(textView.string == "Pay  dues")
    #expect(textView.selectedRange == NSRange(location: start, length: 0))
  }

  private func makeVimMotionTextView(
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

  private func keyEvent(
    characters: String,
    ignoring: String,
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags = []
  ) -> NSEvent {
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: ignoring,
        isARepeat: false,
        keyCode: keyCode
      )
    else { fatalError("failed to create key event") }
    return event
  }
}
