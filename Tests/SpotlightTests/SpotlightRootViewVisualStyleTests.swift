import Testing

@testable import Spotlight

@Suite("Spotlight root visual style")
struct SpotlightRootViewVisualStyleTests {
  @Test("editor card glass tint stays translucent")
  @MainActor
  func editorCardGlassTintStaysTranslucent() {
    #expect(SpotlightRootView.darkGlassTintOpacity <= 0.66)
    #expect(SpotlightRootView.lightGlassTintOpacity <= 0.60)
  }
}
