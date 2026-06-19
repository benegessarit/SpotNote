import AppKit
import Core
import SwiftUI
import Testing

@testable import Spotlight

@MainActor
@Suite("Spotlight root toast overlay")
struct SpotlightRootToastTests {
  @Test("Hermes/Linear toast messages do not trigger panel height callbacks")
  func toastMessagesDoNotTriggerPanelHeightCallbacks() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }

    try await waitUntil { !fixture.recorder.values.isEmpty }
    await settleSwiftUI()
    let stableCallbackCount = fixture.recorder.values.count

    fixture.vimController.showMessage("Sending to Linear", kind: .info, icon: .hermes)
    await settleSwiftUI()
    #expect(fixture.recorder.values.count == stableCallbackCount)

    fixture.vimController.showMessage("Sent to Hermes for Linear", kind: .success, icon: .hermes)
    await settleSwiftUI()
    #expect(fixture.recorder.values.count == stableCallbackCount)
  }

  @Test("legacy hint preference does not render or reserve statusline space")
  func hintPreferenceDoesNotAffectRootHeight() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }

    try await waitUntil { !fixture.recorder.values.isEmpty }
    await settleSwiftUI()
    let stableCallbackCount = fixture.recorder.values.count
    let expectedEditorHeight = EditorMetrics.panelHeight(
      forLines: EditorMetrics.lineCount(in: fixture.session.currentText),
      maxLines: fixture.preferences.maxVisibleLines
    )

    #expect(fixture.preferences.showHints == true)
    #expect(fixture.recorder.values.last == expectedEditorHeight)

    fixture.preferences.showHints = false
    await settleSwiftUI()

    #expect(fixture.recorder.values.count == stableCallbackCount)
  }

  private final class HeightRecorder {
    var values: [CGFloat] = []
  }

  private struct RootFixture {
    let hostingView: NSHostingView<SpotlightRootView>
    let tempDirectory: URL
    let preferences: ThemePreferences
    let session: ChatSession
    let vimController: VimController
    let recorder: HeightRecorder

    @MainActor
    func cleanup() {
      hostingView.removeFromSuperview()
      try? FileManager.default.removeItem(at: tempDirectory)
    }
  }

  private enum FixtureError: Error {
    case defaultsUnavailable
  }

  private func makeFixture() throws -> RootFixture {
    guard let defaults = UserDefaults(suiteName: "test-\(UUID())") else {
      throw FixtureError.defaultsUnavailable
    }
    let tmpDir = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-root-toast-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let vimController = VimController()
    let recorder = HeightRecorder()
    let root = try makeRoot(
      defaults: defaults,
      tmpDir: tmpDir,
      vimController: vimController,
      recorder: recorder
    )
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 400)
    hostingView.layoutSubtreeIfNeeded()
    return RootFixture(
      hostingView: hostingView,
      tempDirectory: tmpDir,
      preferences: root.preferences,
      session: root.session,
      vimController: vimController,
      recorder: recorder
    )
  }

  private func makeRoot(
    defaults: UserDefaults,
    tmpDir: URL,
    vimController: VimController,
    recorder: HeightRecorder
  ) throws -> SpotlightRootView {
    let preferences = ThemePreferences(defaults: defaults)
    return SpotlightRootView(
      focusTrigger: FocusTrigger(),
      preferences: preferences,
      session: ChatSession(store: try ChatStore(directory: tmpDir)),
      shortcuts: ShortcutStore(defaults: defaults),
      find: FindController(),
      fuzzy: FuzzyController(),
      command: CommandController(),
      vimController: vimController,
      onHeightChange: { recorder.values.append($0) },
      onEscape: {},
      onSendLinearTask: { _ in },
      onAppendDailyNote: { _ in URL(fileURLWithPath: "/tmp/spotnote-daily.md") },
      onAppendCompletedItems: { _ in URL(fileURLWithPath: "/tmp/spotnote-completed.md") },
      onAppendTrayNote: { _ in URL(fileURLWithPath: "/tmp/spotnote-tray.md") }
    )
  }

  private func waitUntil(condition: @MainActor @escaping () -> Bool) async throws {
    for _ in 0..<100 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition was not satisfied")
  }

  private func settleSwiftUI() async {
    for _ in 0..<5 { await Task.yield() }
  }
}
