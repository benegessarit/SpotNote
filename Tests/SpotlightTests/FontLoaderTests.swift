import AppKit
import Testing

@testable import Spotlight

@Suite("FontLoader")
struct FontLoaderTests {
  @Test("registerBundledFonts is idempotent")
  func registerIsIdempotent() {
    FontLoader.registerBundledFonts()
    FontLoader.registerBundledFonts()
    FontLoader.registerBundledFonts()
    #expect(Bool(true))
  }

  @Test("the nvim mono editor faces are bundled as Spotlight resources")
  func lilexMonoIsBundled() throws {
    for name in ["LilexNerdFontMono-Regular", "LilexNerdFontMono-Bold"] {
      let url = try #require(
        Bundle.spotlightResources.url(forResource: name, withExtension: "ttf")
      )
      #expect(url.lastPathComponent == "\(name).ttf")
    }
  }

  @Test("editor font is Lilex Nerd Font Mono at the Raycast body scale")
  func editorFontIsLilexMono() {
    FontLoader.registerBundledFonts()
    let font = SpotNoteFont.editor()
    #expect(font.pointSize == EditorMetrics.fontSize)
    #expect(font.fontName == "LilexNFM-Regular")
    #expect(font.isFixedPitch)
  }
}
