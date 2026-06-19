import Testing

@testable import Spotlight

@Suite("Spotlight root visual style")
struct SpotlightRootViewVisualStyleTests {
  @Test("editor card glass tint is light enough to keep the HUD material prominent")
  @MainActor
  func editorCardGlassTintIsLightEnoughToKeepHUDMaterialProminent() {
    #expect(SpotlightRootView.darkGlassTintOpacity == 0.28)
    #expect(SpotlightRootView.lightGlassTintOpacity == 0.26)
  }
}
