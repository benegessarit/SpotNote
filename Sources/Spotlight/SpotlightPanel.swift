import AppKit

/// The main HUD panel: titled with a hidden/transparent title bar so real
/// traffic lights render over the full-bleed SwiftUI surface.
///
/// Overrides `canBecomeKey` so the panel receives keyboard focus reliably.
/// The panel intentionally avoids `.nonactivatingPanel`: SpotNote's HUD must
/// become a real key window when summoned from another app.
final class SpotlightPanel: NSPanel {
  var keyEquivalentHandler: ((NSEvent) -> Bool)?
  /// Installed by the window controller so the red traffic light runs the
  /// controller's close path (previous-app restore, hide notification)
  /// instead of AppKit's bare window close.
  var onCloseRequest: (() -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func close() {
    if let onCloseRequest {
      onCloseRequest()
    } else {
      super.close()
    }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if keyEquivalentHandler?(event) == true { return true }
    return super.performKeyEquivalent(with: event)
  }
}
