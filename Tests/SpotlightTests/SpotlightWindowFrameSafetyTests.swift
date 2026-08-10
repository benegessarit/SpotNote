import AppKit
import Core
import Testing

@testable import Spotlight

/// The window-never-lost contract (teardown P0, 2026-08-09): pinned
/// positions may go stale across screen changes, and a user drag must
/// survive refocus instead of snapping back to the rest position.
@MainActor
@Suite("Spotlight window frame safety", .serialized)
struct SpotlightWindowFrameSafetyTests {
  @Test("clampedFrame always lands inside the visible frame")
  func clampedFrameStaysVisible() {
    let visible = NSRect(x: 0, y: 38, width: 1728, height: 1041)
    var generator = SeededGenerator(seed: 0x5EED)
    for _ in 0..<200 {
      let frame = NSRect(
        x: CGFloat.random(in: -4000...4000, using: &generator),
        y: CGFloat.random(in: -4000...4000, using: &generator),
        width: CGFloat.random(in: 300...920, using: &generator),
        height: CGFloat.random(in: 100...900, using: &generator)
      )
      let clamped = SpotlightWindowController.clampedFrame(frame, into: visible)
      #expect(clamped.minX >= visible.minX)
      #expect(clamped.maxX <= visible.maxX || frame.width > visible.width)
      #expect(clamped.minY >= visible.minY)
      #expect(clamped.maxY <= visible.maxY || frame.height > visible.height)
      #expect(clamped.size == frame.size)
    }
  }

  @Test("a user drag survives refocus; screen change re-clamps an off-screen panel")
  func dragSurvivesRefocusAndScreenChangeReclamps() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    fixture.preferences.dimOnFocusLoss = true
    fixture.controller.openHUD()
    try await waitUntil("panel appears") {
      fixture.controller.panelForTesting?.isVisible == true
    }
    let panel = try #require(fixture.controller.panelForTesting)
    let restingOrigin = panel.frame.origin

    // Simulate a user drag: a non-programmatic setFrame fires didMove,
    // which must adopt BOTH axes into the pin.
    let dragged = panel.frame.offsetBy(dx: -240, dy: 120)
    panel.setFrame(dragged, display: true)
    try await waitUntil("didMove adopts") { panel.frame.origin == dragged.origin }

    // Refocus runs correctDriftIfNeeded; the dragged position must hold.
    fixture.controller.openHUD()
    try await settle(for: .milliseconds(150))
    #expect(panel.frame.origin == dragged.origin)
    #expect(panel.frame.origin != restingOrigin)

    // Strand the panel below every screen, then announce a screen change:
    // the observer must pull it back inside a visible frame.
    let stranded = panel.frame.offsetBy(dx: 0, dy: -6000)
    panel.setFrame(stranded, display: true)
    NotificationCenter.default.post(
      name: NSApplication.didChangeScreenParametersNotification,
      object: NSApp
    )
    try await waitUntil("re-clamped on screen") {
      guard let screen = panel.screen ?? NSScreen.main else { return false }
      return screen.visibleFrame.intersects(panel.frame)
    }
  }

  // MARK: - Fixture (same shape as SpotlightSidebarToggleTests)

  private struct Fixture {
    let controller: SpotlightWindowController
    let preferences: ThemePreferences
    let tempDirectory: URL
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
    guard let defaults = UserDefaults(suiteName: "spotnote-frame-test-\(UUID())") else {
      throw FixtureError.defaultsUnavailable
    }
    let tmpDir = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-frame-test-\(UUID().uuidString)",
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

  private func settle(for duration: Duration) async throws {
    try await Task.sleep(for: duration)
    for _ in 0..<5 { await Task.yield() }
  }

  /// Deterministic RNG so the property test is reproducible.
  private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return state
    }
  }
}
