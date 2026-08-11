import AppKit
import SwiftUI

struct SpotNoteVisualEffectView: NSViewRepresentable {
  var material: NSVisualEffectView.Material = .hudWindow
  var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
  var state: NSVisualEffectView.State = .active

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    Self.configure(view, material: material, blendingMode: blendingMode, state: state)
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    Self.configure(view, material: material, blendingMode: blendingMode, state: state)
  }

  static func configure(
    _ view: NSVisualEffectView,
    material: NSVisualEffectView.Material,
    blendingMode: NSVisualEffectView.BlendingMode,
    state: NSVisualEffectView.State
  ) {
    view.material = material
    view.blendingMode = blendingMode
    view.state = state
    view.isEmphasized = false
  }
}

/// The system glass material (macOS 26 Liquid Glass), shaped by its own
/// corner radius. Raycast's popovers are literally this: their `[macos]`
/// stylesheet puts `-apple-visual-effect: -apple-system-glass-material`
/// on `.popover__webPopover` and the gradient/backdrop-color stack in the
/// sibling rule is the non-macOS fallback -- a solid #333 background
/// could not transmit the ~48% of backdrop the live sheet measures, so
/// glass suppresses it. Matching their material by construction beats
/// re-deriving a (material x tint) approximation.
@available(macOS 26.0, *)
struct SpotNoteGlassBackdrop: NSViewRepresentable {
  var cornerRadius: CGFloat

  func makeNSView(context: Context) -> NSGlassEffectView {
    let view = NSGlassEffectView()
    view.cornerRadius = cornerRadius
    return view
  }

  func updateNSView(_ view: NSGlassEffectView, context: Context) {
    view.cornerRadius = cornerRadius
  }
}
