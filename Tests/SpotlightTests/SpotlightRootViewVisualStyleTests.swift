import Testing

@testable import Spotlight

@Suite("Spotlight root visual style")
struct SpotlightRootViewVisualStyleTests {
  @Test("editor card glass tint stays opaque enough to read over a busy desktop")
  @MainActor
  func editorCardGlassTintIsOpaqueEnoughToReadOverDesktop() {
    #expect(SpotlightRootView.darkGlassTintOpacity == 0.40)
    #expect(SpotlightRootView.lightGlassTintOpacity == 0.40)
  }
}
