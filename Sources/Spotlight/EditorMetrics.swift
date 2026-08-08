import CoreGraphics

/// Shared vertical metrics for the multiline editor and the panel sizing code.
enum EditorMetrics {
  /// Line height used by both the panel-sizing code and the editor's
  /// paragraph style, so rendered text and the panel cap agree exactly.
  /// 41pt is the measured Raycast Notes line pitch (their ~28pt line box
  /// plus per-paragraph spacing); SpotNote applies it uniformly because
  /// the editor draws every logical line as one fixed-height fragment.
  static let lineHeight: CGFloat = 41
  /// Vertical padding between the content area and the rounded-card edge.
  static let verticalInset: CGFloat = 20
  /// The Raycast-style shell is full-bleed: the surface fills the panel,
  /// so there is no shadow gutter between card and panel edge.
  static let outerPadding: CGFloat = 0
  /// Corner radius of the full-bleed panel surface (Raycast Notes look).
  static let surfaceCornerRadius: CGFloat = 16
  /// Fixed height of the Raycast-style title bar (traffic lights, centered
  /// note title, trailing icon pill). Mirrored by the window controller's
  /// `chromeAboveEditor`.
  static let topBarHeight: CGFloat = 60
  /// Fixed height of the Raycast-style bottom bar (character counter,
  /// theme button). Mirrored by the window controller's `chromeBelowEditor`.
  static let bottomBarHeight: CGFloat = 56
  /// Leading padding inside the rounded card. Keep this at zero so the
  /// ruler itself owns the nvim-style sign column from the card edge.
  static let leadingInset: CGFloat = 0
  /// Trailing padding inside the rounded card. Kept narrow so the custom
  /// overlay scroller reads close to the card's right border.
  static let trailingInset: CGFloat = 8
  /// Gap applied to the text view's leading text-container inset when line
  /// numbers are hidden. Keeps text comfortably off the card edge without
  /// reintroducing a checkbox gutter.
  static let textLeadingGap: CGFloat = 37
  /// Font size used for the editor text (Raycast Notes body scale,
  /// measured from live glyph cap heights: ~29px caps at 2x = 20pt).
  static let fontSize: CGFloat = 20
  /// Vim-normal-mode block cursor width. This intentionally reads like a
  /// real block cursor instead of AppKit's default one-pixel insertion bar.
  static let normalModeCursorWidth: CGFloat = 13
  /// Panel width (Raycast Notes window width).
  static let panelWidth: CGFloat = 670
  /// Fixed height of the find-in-note bar (⌘F).
  static let findBarHeight: CGFloat = 40
  /// Minimum default row count for the roomy HUD. Tuned so a short note
  /// opens at roughly the Raycast Notes window height at the 41pt line
  /// pitch.
  static let roomyVisibleLinesFloor = 6

  /// Panel height for `lines` display rows, clamped to the user-selected
  /// visible-line cap while keeping short notes at the default roomy size.
  static func panelHeight(forLines lines: Int, maxLines: Int) -> CGFloat {
    let clampedMax = max(1, maxLines)
    let roomyFloor = min(clampedMax, max(1, roomyVisibleLinesFloor))
    let clamped = min(max(roomyFloor, lines), clampedMax)
    return CGFloat(clamped) * lineHeight + verticalInset * 2 + outerPadding * 2
  }

  static func lineCount(in text: String) -> Int {
    max(1, text.components(separatedBy: "\n").count)
  }
}
