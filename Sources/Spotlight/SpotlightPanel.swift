import AppKit

/// The main HUD panel: borderless with a full-bleed SwiftUI surface; the
/// Raycast-style traffic lights are drawn by the SwiftUI chrome.
///
/// Overrides `canBecomeKey` so the panel receives keyboard focus reliably.
/// The panel intentionally avoids `.nonactivatingPanel`: SpotNote's HUD must
/// become a real key window when summoned from another app.
final class SpotlightPanel: NSPanel {
  var keyEquivalentHandler: ((NSEvent) -> Bool)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if keyEquivalentHandler?(event) == true { return true }
    return super.performKeyEquivalent(with: event)
  }
}
