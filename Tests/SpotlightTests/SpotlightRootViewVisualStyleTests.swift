import Testing

@testable import Spotlight

@Suite("Spotlight root visual style")
struct SpotlightRootViewVisualStyleTests {
  @Test("editor card glass tint leaves the HUD material prominent")
  @MainActor
  func editorCardGlassTintLeavesHUDMaterialProminent() {
    #expect(SpotlightRootView.darkGlassTintOpacity == 0.34)
    #expect(SpotlightRootView.lightGlassTintOpacity == 0.30)
  }
}
