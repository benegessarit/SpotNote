import CoreGraphics

/// Shared vertical metrics for the multiline editor and the panel sizing code.
enum EditorMetrics {
  /// Line height used by both the panel-sizing code and the editor's
  /// paragraph style, so rendered text and the panel cap agree exactly.
  static let lineHeight: CGFloat = 36
  /// Vertical padding between the content area and the rounded-card edge.
  static let verticalInset: CGFloat = 16
  /// Padding between the rounded card and the panel edge (shadow gutter).
  static let outerPadding: CGFloat = 4
  /// Leading padding inside the rounded card. Keep this at zero so the
  /// ruler itself owns the nvim-style sign column from the card edge.
  static let leadingInset: CGFloat = 0
  /// Trailing padding inside the rounded card. Kept narrow so the custom
  /// overlay scroller reads close to the card's right border.
  static let trailingInset: CGFloat = 8
  /// Gap applied to the text view's leading text-container inset when line
  /// numbers are hidden. Keeps text comfortably off the card edge without
  /// reintroducing a checkbox gutter.
  static let textLeadingGap: CGFloat = 32
  /// Font size used for the editor text.
  static let fontSize: CGFloat = 22
  /// Vim-normal-mode block cursor width. This intentionally reads like a
  /// real block cursor instead of AppKit's default one-pixel insertion bar.
  static let normalModeCursorWidth: CGFloat = 13
  /// Panel width.
  static let panelWidth: CGFloat = 760
  /// Fixed height of the find-in-note bar (⌘F).
  static let findBarHeight: CGFloat = 40
  /// Minimum default row count for the roomy HUD. Keeps short inbox-style
  /// notes open at roughly twice the previous four-line panel height.
  static let roomyVisibleLinesFloor = 9

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
