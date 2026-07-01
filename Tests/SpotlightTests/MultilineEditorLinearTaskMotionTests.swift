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
      return ScratchpadHandoffReceipt(captureID: "PER-1", identifier: "PER-1")
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
      return ScratchpadHandoffReceipt(captureID: "PER-2", identifier: "PER-2")
    }

    textView.sendCurrentTaskToLinear(status: .triage, count: 1)
    try await waitUntil { captured.count == 1 }

    #expect(captured.first?.title == "beta")
    #expect(captured.first?.targetStatus == .triage)
    #expect(captured.first?.labels == ["Bio"])
    #expect(captured.first?.dueDate == "2026-06-15")
    #expect(textView.string == "alpha\ngamma")
  }

  @Test("gc handoff targets the Code workspace with a Develop label")
  func gcHandoffTargetsCodeWorkspaceWithDevelopLabel() async throws {
    let textView = makeTextView(text: "- ship the gc motion #SpotNote")
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    var captured: [LinearTaskHandoffRequest] = []
    textView.onSendLinearTask = { request in
      captured.append(request)
      return ScratchpadHandoffReceipt(captureID: "DAB-42", identifier: "DAB-42")
    }

    textView.sendCurrentTaskToLinear(status: .triage, workspace: .code, count: 1)
    try await waitUntil { captured.count == 1 }

    #expect(captured.first?.workspace == .code)
    #expect(captured.first?.targetStatus == .triage)
    #expect(captured.first?.labels == ["Develop", "SpotNote"])
    #expect(captured.first?.title == "ship the gc motion")
    #expect(!textView.string.contains("ship"))
  }

  @Test("a double-fired handoff sends only once (in-flight guard)")
  func doubleFiredHandoffSendsOnce() async throws {
    let textView = makeTextView(text: "- only once please")
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    var captured: [LinearTaskHandoffRequest] = []
    textView.onSendLinearTask = { request in
      captured.append(request)
      return ScratchpadHandoffReceipt(captureID: "PER-3", identifier: "PER-3")
    }

    // Two synchronous presses before the first send's Task runs: the first sets
    // isHandoffInFlight, so the second must be ignored — only one external write.
    textView.sendCurrentTaskToLinear(status: .triage, count: 1)
    textView.sendCurrentTaskToLinear(status: .triage, count: 1)
    try await waitUntil { captured.count == 1 }
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(captured.count == 1)
  }

  @Test("Linear handoff success toast names the created issue")
  func linearHandoffSuccessToastNamesCreatedIssue() async throws {
    let textView = makeTextView(text: "- file this")
    let controller = VimController()
    textView.attachVimController(controller)
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    textView.onSendLinearTask = { _ in
      ScratchpadHandoffReceipt(captureID: "PER-999", identifier: "PER-999")
    }

    textView.sendCurrentTaskToLinear(status: .triage, count: 1)
    try await waitUntil { controller.message?.text == "Created PER-999 in Linear" }

    #expect(controller.message?.kind == .success)
    #expect(textView.string.isEmpty)
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
