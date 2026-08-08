import Testing

@testable import Spotlight

@Suite("Spotlight root visual style")
struct SpotlightRootViewVisualStyleTests {
  @Test("editor card glass tint keeps native translucency without losing text contrast")
  @MainActor
  func editorCardGlassTintBalancesTranslucencyAndContrast() {
    #expect(SpotlightRootView.darkGlassTintOpacity == 0.55)
    #expect(SpotlightRootView.lightGlassTintOpacity == 0.55)
  }
}
