import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor vim paste")
struct MultilineEditorVimPasteTests {
  @Test("p pastes characterwise after the cursor")
  func pasteCharacterwiseAfterCursor() {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setString("XX", forType: .string)
    let textView = makeTextView(text: "alpha", pasteboard: pasteboard)
    textView.setSelectedRange(NSRange(location: 1, length: 0))

    textView.keyDown(with: keyEvent(characters: "p", ignoring: "p", keyCode: 35))

    #expect(textView.string == "alXXpha")
    #expect(textView.selectedRange == NSRange(location: 3, length: 0))
  }

  @Test("p pastes linewise text below the current line")
  func pasteLinewiseBelowCurrentLine() {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setString("paste\n", forType: .string)
    let textView = makeTextView(text: "alpha\nbeta", pasteboard: pasteboard)
    textView.setSelectedRange(NSRange(location: 1, length: 0))

    textView.keyDown(with: keyEvent(characters: "p", ignoring: "p", keyCode: 35))

    #expect(textView.string == "alpha\npaste\nbeta")
    #expect(textView.selectedRange == NSRange(location: ("alpha\n" as NSString).length, length: 0))
  }

  @Test("V yank then p into a blank spacer line consumes that spacer")
  func visualLineYankPasteIntoBlankSpacerConsumesSpacer() {
    let pasteboard = NSPasteboard.withUniqueName()
    let text = "Cure51\nTherapy questionnaire\nPassport forms\n\n# Tray"
    let textView = makeTextView(text: text, pasteboard: pasteboard)
    textView.setSelectedRange(NSRange(location: ("Cure51\nTherapy" as NSString).length, length: 0))

    textView.keyDown(with: keyEvent(characters: "V", ignoring: "v", keyCode: 9, modifiers: .shift))
    textView.keyDown(with: keyEvent(characters: "y", ignoring: "y", keyCode: 16))
    textView.setSelectedRange(
      NSRange(location: ("Cure51\nTherapy questionnaire\nPassport forms\n" as NSString).length, length: 0)
    )
    textView.keyDown(with: keyEvent(characters: "p", ignoring: "p", keyCode: 35))

    #expect(pasteboard.string(forType: .string) == "Therapy questionnaire\n")
    #expect(textView.string == "Cure51\nTherapy questionnaire\nPassport forms\nTherapy questionnaire\n# Tray")
  }

  @Test("linewise p keeps checklist state attached to shifted downstream rows")
  func pasteLinewiseShiftsChecklistState() {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setString("paste\n", forType: .string)
    let textView = makeTextView(
      text: "alpha\nbeta",
      pasteboard: pasteboard,
      checklistLines: [1: .unchecked]
    )
    textView.setSelectedRange(NSRange(location: 1, length: 0))

    textView.keyDown(with: keyEvent(characters: "p", ignoring: "p", keyCode: 35))

    #expect(textView.string == "alpha\npaste\nbeta")
    #expect(textView.checklistLines == [2: .unchecked])
  }

  private func makeTextView(
    text: String,
    pasteboard: NSPasteboard,
    checklistLines: [Int: ChecklistLineState] = [:]
  ) -> PlaceholderTextView {
    let textView = PlaceholderTextView(
      frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 240)
    )
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.vimPasteboard = pasteboard
    textView.checklistLines = checklistLines
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
