import AppKit
import SwiftUI
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor Linear task motions")
struct MultilineEditorLinearTaskMotionTests {
  @Test("status Linear handoff sends the current bullet block with labels and due date")
  func statusLinearHandoffSendsCurrentBulletBlockWithMetadata() async throws {
    let calendar = Calendar(identifier: .gregorian)
    let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14)))
    let textView = makeTextView(
      text: "- alpha\n- beta #Amplify due:tomorrow\n  wrapped context\n- gamma"
    )
    textView.linearTaskToday = today
    textView.setSelectedRange(
      NSRange(
        location: ("- alpha\n- beta #Amplify due:tomorrow\n  wr" as NSString).length,
        length: 0
      )
    )
    var captured: [LinearTaskHandoffRequest] = []
    textView.onSendLinearTask = { request in
      captured.append(request)
    }

    textView.sendCurrentTaskToLinear(status: .done, count: 1)
    try await waitUntil { captured.count == 1 }

    #expect(captured.first?.title == "beta wrapped context")
    #expect(captured.first?.targetStatus == .done)
    #expect(captured.first?.labels == ["Amplify"])
    #expect(captured.first?.dueDate == "2026-06-15")
    #expect(textView.string == "- alpha\n- gamma")
    #expect(textView.checklistLines.isEmpty)
  }

  @Test("status Linear handoff falls back to the current plain line")
  func statusLinearHandoffFallsBackToCurrentPlainLine() async throws {
    let textView = makeTextView(
      text: "alpha\nbeta #Bio due:06-15-2026\ngamma"
    )
    textView.setSelectedRange(NSRange(location: ("alpha\n" as NSString).length, length: 0))
    var captured: [LinearTaskHandoffRequest] = []
    textView.onSendLinearTask = { request in
      captured.append(request)
    }

    textView.sendCurrentTaskToLinear(status: .triage, count: 1)
    try await waitUntil { captured.count == 1 }

    #expect(captured.first?.title == "beta")
    #expect(captured.first?.targetStatus == .triage)
    #expect(captured.first?.labels == ["Bio"])
    #expect(captured.first?.dueDate == "2026-06-15")
    #expect(textView.string == "alpha\ngamma")
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

  private func waitUntil(condition: @MainActor @escaping () -> Bool) async throws {
    for _ in 0..<100 {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for async editor action")
  }
}
