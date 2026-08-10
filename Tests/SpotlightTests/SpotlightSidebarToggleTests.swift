import AppKit
import Core
import Testing

@testable import Spotlight

/// Regression suite for the ⌘\ sidebar bug (2026-08-09): the pref flipped
/// and the panel widened to 920pt, but SwiftUI intermittently never
/// inserted the sidebar -- a 670pt main column floating centered in a
/// 920pt window. The load-bearing ingredient is the controller's
/// `$sidebarShown` sink resizing + displaying the panel during `willSet`,
/// so the repro must drive the REAL `SpotlightWindowController` panel,
/// not a bare hosting view.
@MainActor
@Suite("Sidebar toggle render agreement", .serialized)
struct SpotlightSidebarToggleTests {
  @Test("panel width and sidebar render agree across repeated hotkey-path toggles")
  func widthAndRenderAgreeAcrossToggles() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    fixture.controller.openHUD()
    try await waitUntil("panel appears") { visibleControllerPanel() != nil }
    let panel = try #require(visibleControllerPanel())
    try await waitUntil("editor mounts") { firstTextView(in: panel) != nil }

    // 12 round trips; the live failure hit ~half of attempts, so a
    // consistent pass here must survive repetition, not one lucky toggle.
    for attempt in 0..<12 {
      let target = !fixture.preferences.sidebarShown
      // Mirror the hotkey dispatch shape (SpotlightWindow.swift:631):
      // the toggle runs as its own main-actor job, not inline in an
      // event callback.
      await Task { @MainActor in
        fixture.preferences.sidebarShown = target
      }.value
      await settleSwiftUI()

      let expectedWidth =
        EditorMetrics.panelWidth + (target ? EditorMetrics.sidebarWidth : 0)
      try await waitUntil("width settles (attempt \(attempt))") {
        panel.frame.width == expectedWidth
      }
      // The main column is a fixed 670pt: with the sidebar rendered it
      // starts at x=250, without it at x=0 -- and in the BUG state
      // (wide window, no sidebar) it floats centered at x=125. The
      // editor's NSTextView x-position in window coordinates therefore
      // separates "rendered" from "missing" unambiguously.
      try await waitUntil("render agrees (attempt \(attempt))") {
        guard let textView = firstTextView(in: panel) else { return false }
        let textMinX = textView.convert(textView.bounds, to: nil).minX
        return target ? textMinX > 200 : textMinX < 125
      }
    }
  }

  // MARK: - Fixture

  private struct Fixture {
    let controller: SpotlightWindowController
    let preferences: ThemePreferences
    let tempDirectory: URL

    @MainActor
    func cleanup() {
      for window in NSApplication.shared.windows where window is SpotlightPanel {
        window.orderOut(nil)
      }
      try? FileManager.default.removeItem(at: tempDirectory)
    }
  }

  private enum FixtureError: Error {
    case defaultsUnavailable
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
    return Fixture(controller: controller, preferences: preferences, tempDirectory: tmpDir)
  }

  /// The controller's panel is private; the suite runs serialized and no
  /// other suite mounts a full root view into a `SpotlightPanel`, so the
  /// visible panel hosting an editor text view is unambiguous.
  private func visibleControllerPanel() -> SpotlightPanel? {
    NSApplication.shared.windows
      .compactMap { $0 as? SpotlightPanel }
      .first { $0.isVisible && firstTextView(in: $0) != nil }
  }

  private func firstTextView(in panel: NSPanel) -> PlaceholderTextView? {
    guard let content = panel.contentView else { return nil }
    return firstTextView(in: content)
  }

  private func firstTextView(in view: NSView) -> PlaceholderTextView? {
    if let match = view as? PlaceholderTextView { return match }
    for subview in view.subviews {
      if let match = firstTextView(in: subview) { return match }
    }
    return nil
  }

  private func waitUntil(
    _ label: String,
    condition: @MainActor @escaping () -> Bool
  ) async throws {
    for _ in 0..<300 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out waiting: \(label)")
  }

  private func settleSwiftUI() async {
    for _ in 0..<5 { await Task.yield() }
  }
}
