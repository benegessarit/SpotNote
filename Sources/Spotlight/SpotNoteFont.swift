import AppKit

enum SpotNoteFont {
  /// Primary editor face: MonoLisa, a licensed font the user installs into
  /// ~/Library/Fonts. We deliberately do NOT bundle/redistribute a paid font,
  /// so it resolves from the system install (bold/italic weights too, which the
  /// code stylers derive via NSFontManager trait conversion).
  static let editorFontName = "MonoLisa-Regular"

  /// Bundled fallback when MonoLisa is not installed: IBM Plex Mono ships in
  /// Resources (registered process-locally by FontLoader) so the HUD always has
  /// a fixed-pitch face even on a Mac without MonoLisa.
  static let fallbackFontName = "IBMPlexMono"

  static func editor(size: CGFloat = EditorMetrics.fontSize) -> NSFont {
    FontLoader.registerBundledFonts()
    return NSFont(name: editorFontName, size: size)
      ?? NSFont(name: fallbackFontName, size: size)
      ?? .monospacedSystemFont(ofSize: size, weight: .regular)
  }
}
