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
