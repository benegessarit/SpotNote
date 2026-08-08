import AppKit

enum SpotNoteFont {
  /// Primary editor face: the system sans (SF Pro), matching the Raycast
  /// Notes body text. The former MonoLisa/IBM Plex Mono monospace chain was
  /// retired with the Raycast shell (2026-08-08); bold/italic weights still
  /// derive via NSFontManager trait conversion in the code stylers.
  static func editor(size: CGFloat = EditorMetrics.fontSize) -> NSFont {
    .systemFont(ofSize: size)
  }
}
