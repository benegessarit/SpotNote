import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor visual mode highlighting")
struct MultilineEditorVisualModeTests {
  @Test("v highlights characterwise and motions extend one character at a time")
  func visualCharacterModeHighlightsCharacterwise() {
    let textView = makeTextView(text: "alpha\nbeta")
    textView.setSelectedRange(NSRange(location: 1, length: 0))

    textView.keyDown(with: keyEvent(characters: "v", ignoring: "v", keyCode: 9))

    #expect(textView.vimEngine?.mode == .visual)
    #expect(textView.selectedRange == NSRange(location: 1, length: 1))

    textView.keyDown(with: keyEvent(characters: "l", ignoring: "l", keyCode: 37))

    #expect(textView.selectedRange == NSRange(location: 1, length: 2))

    textView.keyDown(with: keyEvent(characters: "h", ignoring: "h", keyCode: 4))
    textView.keyDown(with: keyEvent(characters: "h", ignoring: "h", keyCode: 4))

    #expect(textView.selectedRange == NSRange(location: 0, length: 2))
  }

  @Test("v dollar highlights through line text without swallowing the newline")
  func visualCharacterLineEndStopsBeforeNewline() {
    let textView = makeTextView(text: "alpha\nbeta")
    textView.setSelectedRange(NSRange(location: 1, length: 0))

    textView.keyDown(with: keyEvent(characters: "v", ignoring: "v", keyCode: 9))
    textView.keyDown(with: keyEvent(characters: "$", ignoring: "$", keyCode: 21, modifiers: .shift))

    #expect(textView.selectedRange == NSRange(location: 1, length: 4))
    #expect((textView.string as NSString).substring(with: textView.selectedRange) == "lpha")
  }

  @Test("V highlights the full current line")
  func visualLineModeHighlightsWholeLine() {
    let text = "alpha\nbeta\ngamma"
    let textView = makeTextView(text: text)
    textView.setSelectedRange(NSRange(location: ("alpha\nb" as NSString).length, length: 0))

    textView.keyDown(with: keyEvent(characters: "V", ignoring: "v", keyCode: 9, modifiers: .shift))

    let expectedLine = (text as NSString).lineRange(
      for: NSRange(location: ("alpha\nb" as NSString).length, length: 0)
    )
    #expect(textView.vimEngine?.mode == .visualLine)
    #expect(textView.selectedRange == expectedLine)
  }

  private func makeTextView(text: String) -> PlaceholderTextView {
    let textView = PlaceholderTextView(
      frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 240)
    )
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    CodeStyler.apply(to: textView, theme: ThemeCatalog.obsidian)
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
