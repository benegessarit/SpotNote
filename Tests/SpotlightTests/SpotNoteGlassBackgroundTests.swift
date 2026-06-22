import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("SpotNote glass background")
struct SpotNoteGlassBackgroundTests {
  @Test("visual effect view uses HUD material behind the window")
  func visualEffectViewUsesHUDMaterial() {
    let view = NSVisualEffectView()

    SpotNoteVisualEffectView.configure(
      view,
      material: .hudWindow,
      blendingMode: .behindWindow,
      state: .active
    )

    #expect(view.material == .hudWindow)
    #expect(view.blendingMode == .behindWindow)
    #expect(view.state == .active)
    #expect(view.isEmphasized == false)
  }
}
