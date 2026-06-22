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

  @Test("editor font requests MonoLisa by PostScript name, IBM Plex Mono as fallback")
  func editorFontRequestsMonoLisa() {
    #expect(SpotNoteFont.editorFontName == "MonoLisa-Regular")
    #expect(SpotNoteFont.fallbackFontName == "IBMPlexMono")
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

  @Test("editor font resolves to MonoLisa, then IBM Plex Mono, then any fixed pitch")
  func editorFontResolvesToMonoLisa() {
    let font = SpotNoteFont.editor(size: 22)
    if NSFont(name: SpotNoteFont.editorFontName, size: 22) != nil {
      #expect(font.fontName == SpotNoteFont.editorFontName)
      #expect(font.familyName == "MonoLisa")
    } else if NSFont(name: SpotNoteFont.fallbackFontName, size: 22) != nil {
      #expect(font.fontName == SpotNoteFont.fallbackFontName)
      #expect(font.familyName == "IBM Plex Mono")
    } else {
      #expect(font.isFixedPitch)
    }
  }
}
