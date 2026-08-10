import AppKit
import Core
import Testing

@testable import Spotlight

/// Regression suite for ⌘\ sidebar behavior. History: the in-window
/// sidebar's width sink rendered one state behind (2026-08-09, S2); the
/// sidebar is now a SHELF child panel with its own height (S6) -- the
/// window must never widen, and the shelf's presence must agree with the
/// preference across repeated hotkey-path toggles.
@MainActor
@Suite("Sidebar shelf toggle agreement", .serialized)
struct SpotlightSidebarToggleTests {
  @Test("shelf presence and window width agree across repeated hotkey-path toggles")
  func shelfAndWidthAgreeAcrossToggles() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    // A resign mid-run (David clicking elsewhere during an attended
    // ci.sh) must only dim the panel, not close/hide the app under the
    // remaining toggles; frame assertions are alpha-independent.
    fixture.preferences.dimOnFocusLoss = true
    fixture.controller.openHUD()
    try await waitUntil("panel appears") {
      fixture.controller.panelForTesting?.isVisible == true
    }
    let panel = try #require(fixture.controller.panelForTesting)

    // 12 round trips; the historical failure hit ~half of attempts, so a
    // consistent pass here must survive repetition, not one lucky toggle.
    for attempt in 0..<12 {
      let target = !fixture.preferences.sidebarShown
      // Mirror the hotkey dispatch shape (`handleKeyEquivalent` →
      // `dispatch`): the toggle runs as its own main-actor job, not
      // inline in an event callback.
      await Task { @MainActor in
        fixture.preferences.sidebarShown = target
      }.value
      await settleSwiftUI()

      // Structural assertions only: interleaved @MainActor suites can
      // hide the app mid-run (another fixture's `close()`), so
      // window-server visibility is not a stable signal here -- shelf
      // existence and geometry are.
      try await waitUntil("shelf agrees (attempt \(attempt))") {
        let shelf = fixture.controller.sidebarShelfForTesting
        return target ? shelf != nil : shelf == nil
      }
      // The shelf never widens the window: the S6 contract.
      #expect(panel.frame.width == EditorMetrics.panelWidth)
      if target {
        let shelf = try #require(fixture.controller.sidebarShelfForTesting)
        #expect(shelf.frame.width == EditorMetrics.sidebarWidth)
        #expect(shelf.frame.height == EditorMetrics.sidebarShelfHeight)
        // The shelf hangs off the LEFT edge, never over the note.
        #expect(shelf.frame.maxX <= panel.frame.minX)
        if panel.isVisible {
          #expect(shelf.parent === panel)
        }
      }
    }
  }

  @Test("closing the HUD dismisses the shelf; reopening restores it")
  func shelfFollowsHUDLifecycle() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    fixture.preferences.dimOnFocusLoss = true
    fixture.preferences.sidebarShown = true
    fixture.controller.openHUD()
    try await waitUntil("shelf appears") {
      fixture.controller.sidebarShelfForTesting != nil
    }

    fixture.controller.close()
    try await waitUntil("shelf dismissed") {
      fixture.controller.sidebarShelfForTesting == nil
    }

    fixture.controller.openHUD()
    try await waitUntil("shelf restored") {
      fixture.controller.sidebarShelfForTesting != nil
    }
  }

  // MARK: - Fixture

  private struct Fixture {
    let controller: SpotlightWindowController
    let preferences: ThemePreferences
    let tempDirectory: URL
    /// Frontmost app before `openHUD` steals activation; cleanup hands
    /// focus back so an attended test run doesn't strand keystrokes.
    let previouslyFrontmost: NSRunningApplication?

    @MainActor
    func cleanup() {
      for window in NSApplication.shared.windows where window is SpotlightPanel {
        window.orderOut(nil)
      }
      let ownBundle = Bundle.main.bundleIdentifier
      if let app = previouslyFrontmost, app.bundleIdentifier != ownBundle {
        app.activate()
      }
      try? FileManager.default.removeItem(at: tempDirectory)
    }
  }

  private enum FixtureError: Error {
    case defaultsUnavailable
    case timedOut(String)
  }

  private func makeFixture() throws -> Fixture {
    guard let defaults = UserDefaults(suiteName: "spotnote-sidebar-test-\(UUID())") else {
      throw FixtureError.defaultsUnavailable
    }
    let tmpDir = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-sidebar-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let preferences = ThemePreferences(defaults: defaults)
    let controller = SpotlightWindowController(
      preferences: preferences,
      store: try ChatStore(directory: tmpDir),
      shortcuts: ShortcutStore(defaults: defaults),
      onOpenSettings: {}
    )
    return Fixture(
      controller: controller,
      preferences: preferences,
      tempDirectory: tmpDir,
      previouslyFrontmost: NSWorkspace.shared.frontmostApplication
    )
  }

  /// Throws on timeout so one broken invariant aborts the toggle loop
  /// instead of accumulating twelve timeouts of duplicate issues.
  private func waitUntil(
    _ label: String,
    condition: @MainActor @escaping () -> Bool
  ) async throws {
    for _ in 0..<300 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw FixtureError.timedOut(label)
  }

  private func settleSwiftUI() async {
    for _ in 0..<5 { await Task.yield() }
  }
}
