import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor tray-note append")
struct MultilineEditorTrayNoteAppendTests {
  @Test("append-to-tray-note sends current line and clears only after success")
  func appendTrayNoteClearsAfterSuccess() async throws {
    let textView = makeTextView(
      text: "alpha\nbeta\ngamma",
      checklistLines: [1: .unchecked]
    )
    textView.setSelectedRange(NSRange(location: ("alpha\n" as NSString).length, length: 0))
    var captured: [String] = []
    textView.onAppendTrayNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/tray.md")
    }

    textView.appendCurrentLinesToTrayNote(1)
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["beta"])
    #expect(textView.string == "alpha\ngamma")
    #expect(textView.checklistLines.isEmpty)
  }

  @Test("append-to-tray-note sends the current bullet block")
  func appendTrayNoteSendsCurrentBulletBlock() async throws {
    let text = "plain\n- beta\n  wrapped context\n  - nested child\n- gamma"
    let textView = makeTextView(text: text)
    textView.setSelectedRange(NSRange(location: ("plain\n- beta\n  wrapped" as NSString).length, length: 0))
    var captured: [String] = []
    textView.onAppendTrayNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/tray.md")
    }

    textView.appendCurrentLinesToTrayNote(1)
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["- beta\n  wrapped context\n  - nested child"])
    #expect(textView.string == "plain\n- gamma")
  }

  @Test("gy motion sends the current bullet block to tray.md")
  func gyMotionSendsCurrentBulletBlockToTrayNote() async throws {
    let text = "plain\n- beta\n  wrapped context\n- gamma"
    let textView = makeTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: ("plain\n- beta\n  wrapped" as NSString).length, length: 0))
    var captured: [String] = []
    textView.onAppendTrayNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/tray.md")
    }

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "y", ignoring: "y", keyCode: 16))
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["- beta\n  wrapped context"])
    #expect(textView.string == "plain\n- gamma")
  }

  @Test("append-to-tray-note sends an active visual selection exactly")
  func appendTrayNoteSendsActiveVisualSelectionExactly() async throws {
    let textView = makeTextView(text: "alpha\nbeta details\ngamma")
    let selection = NSRange(location: ("alpha\nbeta " as NSString).length, length: ("details" as NSString).length)
    textView.setSelectedRange(selection)
    var captured: [String] = []
    textView.onAppendTrayNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/tray.md")
    }

    textView.appendCurrentLinesToTrayNote(1)
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["details"])
    #expect(textView.string == "alpha\nbeta \ngamma")
  }

  @Test("append-to-tray-note supports counted lines")
  func appendTrayNoteSupportsCountedLines() async throws {
    let textView = makeTextView(text: "alpha\nbeta\ngamma\ndelta")
    textView.setSelectedRange(NSRange(location: ("alpha\n" as NSString).length, length: 0))
    var captured: [String] = []
    textView.onAppendTrayNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/tray.md")
    }

    textView.appendCurrentLinesToTrayNote(2)
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["beta\ngamma"])
    #expect(textView.string == "alpha\ndelta")
  }

  @Test("append-to-tray-note keeps text when durable write fails")
  func appendTrayNoteKeepsTextOnFailure() async throws {
    struct StubFailure: Error {}
    let textView = makeTextView(text: "alpha\nbeta\ngamma")
    textView.setSelectedRange(NSRange(location: ("alpha\n" as NSString).length, length: 0))
    var attempts = 0
    textView.onAppendTrayNote = { _ in
      attempts += 1
      throw StubFailure()
    }

    textView.appendCurrentLinesToTrayNote(1)
    try await waitUntil { attempts == 1 }

    #expect(textView.string == "alpha\nbeta\ngamma")
  }

  private func makeTextView(
    text: String,
    checklistLines: [Int: ChecklistLineState] = [:]
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

  private func keyEvent(characters: String, ignoring: String, keyCode: UInt16) -> NSEvent {
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
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

  private func waitUntil(condition: @MainActor @escaping () -> Bool) async throws {
    for _ in 0..<100 {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for async editor action")
  }
}
