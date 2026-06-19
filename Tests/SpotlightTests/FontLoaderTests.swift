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

  @Test("editor font requests IBM Plex Mono by PostScript name")
  func editorFontRequestsIBMPlexMono() {
    #expect(SpotNoteFont.editorFontName == "IBMPlexMono")
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

  @Test("editor font resolves to IBM Plex Mono when available on this Mac")
  func editorFontResolvesToIBMPlexMono() {
    let font = SpotNoteFont.editor(size: 22)
    if NSFont(name: SpotNoteFont.editorFontName, size: 22) != nil {
      #expect(font.fontName == "IBMPlexMono")
      #expect(font.familyName == "IBM Plex Mono")
    } else {
      #expect(font.isFixedPitch)
    }
  }
}
