import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor Return key handling")
struct MultilineEditorReturnKeyTests {
  @Test("Return key in Vim insert mode splits text at the caret")
  func returnKeyInVimInsertModeSplitsTextAtCaret() {
    let text = [
      "## To Do",
      "Mireya BGA follow upCalendly for game night",
      "Passport forms",
      "",
      "# Tray"
    ].joined(separator: "\n")
    let textView = makeTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.keyDown(with: keyEvent(characters: "i", ignoring: "i", keyCode: 34))
    let split = ("## To Do\nMireya BGA follow up" as NSString).length
    textView.setSelectedRange(NSRange(location: split, length: 0))

    textView.keyDown(with: keyEvent(characters: "\r", ignoring: "\r", keyCode: 36))

    #expect(
      textView.string
        == [
          "## To Do",
          "Mireya BGA follow up",
          "Calendly for game night",
          "Passport forms",
          "",
          "# Tray"
        ].joined(separator: "\n")
    )
    #expect(textView.selectedRange.location == split + 1)
  }

  private func makeTextView(text: String) -> PlaceholderTextView {
    let textView = PlaceholderTextView(
      frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 240)
    )
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text

    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
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
