import AppKit

enum SpotNoteFont {
  static let editorFontName = "IBMPlexMono"

  static func editor(size: CGFloat = EditorMetrics.fontSize) -> NSFont {
    FontLoader.registerBundledFonts()
    return NSFont(name: editorFontName, size: size)
      ?? .monospacedSystemFont(ofSize: size, weight: .regular)
  }
}
