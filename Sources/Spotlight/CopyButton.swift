import AppKit
import Combine

/// Shared copy path for keyboard/menu actions. The HUD no longer shows an
/// in-editor copy button, but copy still routes through one controller so
/// the pasteboard behavior stays centralized.
@MainActor
final class CopyController: ObservableObject {
  @Published private(set) var feedbackTick: Int = 0

  /// Writes `text` to the general pasteboard (no-op when empty) and
  /// records a copy event. Caller decides whether to copy the full note or
  /// just a selection -- see `SpotlightWindowController.dispatch`.
  func copy(_ text: String) {
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    feedbackTick &+= 1
  }
}
