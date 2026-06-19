import AppKit
import Testing

@testable import Spotlight

@Suite("Checklist document adapter")
struct ChecklistDocumentTests {
  @Test("parse strips line-start Markdown markers into line states")
  func parseMarkdownIntoVisibleTextAndStates() {
    let document = ChecklistDocument.parseMarkdown(
      "[ ] open\n[ x ] done\narray[x] stays text\n  [x] indented"
    )

    #expect(document.text == "open\ndone\narray[x] stays text\n  indented")
    #expect(document.checklistLines == [0: .unchecked, 1: .checked, 3: .checked])
  }

  @Test("serialize inserts Markdown markers at the first non-space column")
  func serializeLineStatesIntoMarkdownMarkers() {
    let markdown = ChecklistDocument.serializeMarkdown(
      text: "open\ndone\narray[x] stays text\n  indented",
      checklistLines: [0: .unchecked, 1: .checked, 3: .checked]
    )

    #expect(markdown == "[   ] open\n[ x ] done\narray[x] stays text\n  [ x ] indented")
  }
}

@MainActor
@Suite("Icon-only checklist line state")
struct ChecklistLineStateEditorTests {
  @Test("vim o on a checklist last line opens a same-row editable checklist line")
  func vimOpenLineBelowCarriesChecklistStateWithoutHiddenText() {
    let textView = makeTextView(
      text: "Pass email\nPick AirBnb\nCall Justin",
      checklistLines: [0: .unchecked, 1: .unchecked, 2: .unchecked]
    )
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    let callStart = ("Pass email\nPick AirBnb\n" as NSString).length
    textView.setSelectedRange(NSRange(location: callStart, length: 0))

    textView.keyDown(with: keyEvent(characters: "o", ignoring: "o", keyCode: 31))

    #expect(textView.string == "Pass email\nPick AirBnb\nCall Justin\n")
    #expect(textView.selectedRange.location == (textView.string as NSString).length)
    #expect(
      textView.checklistLines == [
        0: .unchecked,
        1: .unchecked,
        2: .unchecked,
        3: .unchecked
      ]
    )
  }

  @Test("vim o on the To Do heading keeps existing checkbox states on task text")
  func vimOpenLineBelowHeadingKeepsChecklistStatesAlignedWithTaskText() {
    let textView = makeTextView(
      text: "## To Do\nPass email\nPick AirBnb",
      checklistLines: [1: .unchecked, 2: .checked]
    )
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "o", ignoring: "o", keyCode: 31))

    #expect(textView.string == "## To Do\n\nPass email\nPick AirBnb")
    #expect(textView.selectedRange.location == ("## To Do\n" as NSString).length)
    #expect(textView.checklistLines == [2: .unchecked, 3: .checked])
  }

  @Test("vim o on To Do above an empty checkbox row creates a plain blank row")
  func vimOpenLineBelowHeadingShiftsEmptyCheckboxRowOutOfInsertedBlankLine() {
    let textView = makeTextView(
      text: "## To Do\n",
      checklistLines: [1: .unchecked]
    )
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "o", ignoring: "o", keyCode: 31))

    #expect(textView.string == "## To Do\n\n")
    #expect(textView.selectedRange.location == ("## To Do\n" as NSString).length)
    let caret = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )
    #expect(abs(caret.origin.y - EditorMetrics.lineHeight) < 0.001)
    #expect(textView.checklistLines == [2: .unchecked])
  }

  @Test("vim O inserts a checklist line above and shifts the existing state down")
  func vimOpenLineAboveCarriesChecklistStateWithoutHiddenText() {
    let textView = makeTextView(
      text: "Pick AirBnb",
      checklistLines: [0: .checked]
    )
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "O", ignoring: "O", keyCode: 31, modifiers: .shift))

    #expect(textView.string == "\nPick AirBnb")
    #expect(textView.selectedRange.location == 0)
    #expect(textView.checklistLines == [0: .unchecked, 1: .checked])
  }

  private func makeTextView(
    text: String,
    checklistLines: [Int: ChecklistLineState]
  ) -> PlaceholderTextView {
    let textView = PlaceholderTextView(
      frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 200)
    )
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text
    textView.checklistLines = checklistLines
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
