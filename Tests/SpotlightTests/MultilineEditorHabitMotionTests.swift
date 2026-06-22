import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor habit motion")
struct MultilineEditorHabitMotionTests {
  @Test("\\h logs the current habit bullet and clears it")
  func backslashHLogsCurrentHabitAndClears() async throws {
    let textView = makeTextView(text: "## Habits\n- Piano practice @15m\n- Meditate/jhana")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(
      NSRange(location: ("## Habits\n- Piano prac" as NSString).length, length: 0)
    )
    var captured: [HabitHandoffRequest] = []
    textView.onSendHabit = { request in
      captured.append(request)
    }

    textView.keyDown(with: keyEvent(characters: "\\", ignoring: "\\", keyCode: 42))
    textView.keyDown(with: keyEvent(characters: "h", ignoring: "h", keyCode: 4))
    try await waitUntil { captured.count == 1 }

    // The bullet is sent verbatim (markers stripped) and cleared after handoff —
    // David re-adds habits the next day.
    #expect(captured.first?.habit == "Piano practice @15m")
    #expect(textView.string == "## Habits\n- Meditate/jhana")
  }

  @Test("habit handoff prompt names the tracker CLI and carries the bullet verbatim")
  func habitPromptShape() throws {
    let prompt = HabitHandoffPrompt.render(habit: "Cardio with 3brown1blue")
    #expect(prompt.contains("life_dashboard_habits.py done"))
    #expect(prompt.contains("Cardio with 3brown1blue"))
    // Explicitly steers the agent away from the Linear/daily-note paths.
    #expect(prompt.contains("do NOT create a Linear issue"))
  }

  @Test("empty habit request is rejected by the payload builder")
  func emptyHabitRejected() {
    #expect(throws: ScratchpadHandoffError.emptyText) {
      _ = try ScratchpadHandoffClient.payload(forHabit: HabitHandoffRequest(habit: "   "), id: "x")
    }
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
