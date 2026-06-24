import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor State-note append")
struct MultilineEditorStateNoteAppendTests {
  @Test("\\c flattens the current bullet block to one `- ` line and clears after success")
  func stateAppendFlattensAndClearsAfterSuccess() async throws {
    let text = "plain\n- beta #tag\n  wrapped context\n- gamma"
    let textView = makeTextView(text: text)
    textView.setSelectedRange(
      NSRange(location: ("plain\n- beta #tag\n  wr" as NSString).length, length: 0)
    )
    var captured: [String] = []
    textView.onAppendStateNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/state.md")
    }

    textView.appendCurrentLinesToStateNote(1)
    try await waitUntil { captured.count == 1 }

    // bullet marker stripped, continuation folded into one `- ` line; a typed
    // #tag is preserved (State.md is plain markdown — only the Linear motions
    // strip #labels).
    #expect(captured == ["- beta #tag wrapped context"])
    #expect(textView.string == "plain\n- gamma")
  }

  @Test("counted \\c files N separate `- ` lines, not one fused line")
  func stateAppendCountFilesSeparateLines() async throws {
    let textView = makeTextView(text: "- alpha\n- beta\n- gamma")
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    var captured: [String] = []
    textView.onAppendStateNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/state.md")
    }

    textView.appendCurrentLinesToStateNote(2)
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["- alpha\n- beta"])  // two separate bullets, never "- alpha beta"
    #expect(textView.string == "- gamma")
  }

  @Test("\\c keeps the source bullet when the durable write fails")
  func stateAppendKeepsTextOnFailure() async throws {
    struct StubFailure: Error {}
    let textView = makeTextView(text: "alpha\n- beta\ngamma")
    textView.setSelectedRange(NSRange(location: ("alpha\n" as NSString).length, length: 0))
    var attempts = 0
    textView.onAppendStateNote = { _ in
      attempts += 1
      throw StubFailure()
    }

    textView.appendCurrentLinesToStateNote(1)
    try await waitUntil { attempts == 1 }

    #expect(textView.string == "alpha\n- beta\ngamma")
  }

  @Test("\\c motion via keystrokes files the current bullet to State.md")
  func backslashCMotionFilesCurrentBullet() async throws {
    let textView = makeTextView(text: "plain\n- beta\n- gamma")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: ("plain\n- be" as NSString).length, length: 0))
    var captured: [String] = []
    textView.onAppendStateNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/state.md")
    }

    textView.keyDown(with: keyEvent(characters: "\\", ignoring: "\\", keyCode: 42))
    textView.keyDown(with: keyEvent(characters: "c", ignoring: "c", keyCode: 8))
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["- beta"])
    #expect(textView.string == "plain\n- gamma")
  }

  @Test("stateNotePayload: single bullet block flattens to one `- ` line with no newline")
  func payloadSingleBlockHasNoNewline() {
    // Bullet marker stripped + continuation folded; a typed #tag stays (not a Linear send).
    let payload = PlaceholderTextView.stateNotePayload(from: "- beta #tag\n  wrapped context")
    #expect(payload == "- beta #tag wrapped context")
    #expect(payload?.contains("\n") == false)
  }

  @Test("stateNotePayload: three blocks become three `- ` lines")
  func payloadThreeBlocks() {
    let payload = PlaceholderTextView.stateNotePayload(from: "- a\n- b\n- c")
    #expect(payload == "- a\n- b\n- c")
  }

  @Test("stateNotePayload: plain non-indented lines each become their own `- ` line")
  func payloadPlainLinesSeparate() {
    let payload = PlaceholderTextView.stateNotePayload(from: "alpha\nbeta")
    #expect(payload == "- alpha\n- beta")
  }

  @Test("stateNotePayload: blank-only input is nil")
  func payloadBlankIsNil() {
    #expect(PlaceholderTextView.stateNotePayload(from: "  \n\n") == nil)
  }

  private func makeTextView(text: String) -> PlaceholderTextView {
    let textView = PlaceholderTextView(
      frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 200)
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
