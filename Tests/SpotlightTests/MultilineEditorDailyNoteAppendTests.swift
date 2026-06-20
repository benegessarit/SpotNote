import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor daily-note append")
struct MultilineEditorDailyNoteAppendTests {
  @Test("append-to-daily-note sends current line and clears only after success")
  func appendDailyNoteClearsAfterSuccess() async throws {
    let textView = makeTextView(text: "alpha\nbeta\ngamma")
    textView.setSelectedRange(NSRange(location: ("alpha\n" as NSString).length, length: 0))
    var captured: [String] = []
    textView.onAppendDailyNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/06-15-2026.md")
    }

    textView.appendCurrentLinesToDailyNote(1)
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["beta"])
    #expect(textView.string == "alpha\ngamma")
  }

  @Test("append-to-daily-note keeps text when durable write fails")
  func appendDailyNoteKeepsTextOnFailure() async throws {
    struct StubFailure: Error {}
    let textView = makeTextView(text: "alpha\nbeta\ngamma")
    textView.setSelectedRange(NSRange(location: ("alpha\n" as NSString).length, length: 0))
    var attempts = 0
    textView.onAppendDailyNote = { _ in
      attempts += 1
      throw StubFailure()
    }

    textView.appendCurrentLinesToDailyNote(1)
    try await waitUntil { attempts == 1 }

    #expect(textView.string == "alpha\nbeta\ngamma")
  }

  @Test("append-to-daily-note preserves indentation before clearing")
  func appendDailyNotePreservesIndentationBeforeClearing() async throws {
    let textView = makeTextView(text: "alpha\n    let answer = 42\ngamma")
    textView.setSelectedRange(NSRange(location: ("alpha\n" as NSString).length, length: 0))
    var captured: [String] = []
    textView.onAppendDailyNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/06-15-2026.md")
    }

    textView.appendCurrentLinesToDailyNote(1)
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["    let answer = 42"])
    #expect(textView.string == "alpha\ngamma")
  }

  @Test("append-to-daily-note supports counted lines")
  func appendDailyNoteSupportsCountedLines() async throws {
    let textView = makeTextView(text: "alpha\nbeta\ngamma\ndelta")
    textView.setSelectedRange(NSRange(location: ("alpha\n" as NSString).length, length: 0))
    var captured: [String] = []
    textView.onAppendDailyNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/06-15-2026.md")
    }

    textView.appendCurrentLinesToDailyNote(2)
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["beta\ngamma"])
    #expect(textView.string == "alpha\ndelta")
  }

  @Test("append-to-daily-note serializes selected checklist lines as Markdown")
  func appendDailyNoteSerializesChecklistLines() async throws {
    let textView = makeTextView(
      text: "alpha\nbeta\ngamma",
      checklistLines: [1: .checked]
    )
    textView.setSelectedRange(NSRange(location: ("alpha\n" as NSString).length, length: 0))
    var captured: [String] = []
    textView.onAppendDailyNote = { text in
      captured.append(text)
      return URL(fileURLWithPath: "/tmp/06-15-2026.md")
    }

    textView.appendCurrentLinesToDailyNote(1)
    try await waitUntil { captured.count == 1 }

    #expect(captured == ["[ x ] beta"])
    #expect(textView.string == "alpha\ngamma")
    #expect(textView.checklistLines.isEmpty)
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

  private func waitUntil(condition: @MainActor @escaping () -> Bool) async throws {
    for _ in 0..<100 {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for async editor action")
  }
}
