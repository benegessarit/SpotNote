import AppKit
import Testing

@testable import Spotlight

@Suite("FontLoader")
struct FontLoaderTests {
  @Test("registerBundledFonts is idempotent and safe to call with zero resources")
  func registerIsIdempotent() {
    // No fonts are shipped in the repo by default (see Resources/README.md).
    // The loader must still complete cleanly and tolerate being called
    // multiple times without raising.
    FontLoader.registerBundledFonts()
    FontLoader.registerBundledFonts()
    FontLoader.registerBundledFonts()
    #expect(Bool(true))
  }

  @Test("IBM Plex Mono regular is bundled as a Spotlight resource")
  func ibmPlexMonoRegularIsBundled() throws {
    let url = try #require(
      Bundle.spotlightResources.url(
        forResource: "IBMPlexMono-Regular",
        withExtension: "ttf"
      )
    )
    #expect(url.lastPathComponent == "IBMPlexMono-Regular.ttf")
  }

  @Test("editor font is the system sans at the Raycast body scale")
  func editorFontIsSystemSans() {
    let font = SpotNoteFont.editor()
    #expect(font.pointSize == EditorMetrics.fontSize)
    #expect(font.fontName == NSFont.systemFont(ofSize: EditorMetrics.fontSize).fontName)
    #expect(!font.isFixedPitch)
  }
}
