import AppKit

enum SpotNoteFont {
  /// Primary editor face: Lilex Nerd Font Mono -- the SAME face David's
  /// nvim renders in (Ghostty `font-family`), restoring the mono grid on
  /// David's order (2026-08-10 "switch to mono grid and use the same mono
  /// font as my nvim") after the proportional editor made the hop/flash
  /// letter hints gappy. Regular + Bold ship in Resources and register
  /// through `FontLoader`; bold/italic weights derive via NSFontManager
  /// trait conversion (the family carries true Bold/Italic faces). The
  /// chrome stays Inter (`RaycastFont`) -- only the note body is mono.
  /// Fallback is the system MONO face so the grid survives a bad bundle.
  static func editor(size: CGFloat = EditorMetrics.fontSize) -> NSFont {
    NSFont(name: "LilexNFM-Regular", size: size)
      ?? .monospacedSystemFont(ofSize: size, weight: .regular)
  }
}
