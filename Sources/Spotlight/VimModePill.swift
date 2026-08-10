import SwiftUI

/// Fixed-length vector so SwiftUI can spring-animate a 3-line glyph's 12
/// coordinates (flubber-style equal-point morphing: every letter is
/// exactly three lines; letters needing fewer collapse an extra line onto
/// an existing one so it morphs out invisibly).
struct AnimatableVector12: VectorArithmetic {
  var values: [CGFloat]

  static var zero: AnimatableVector12 {
    AnimatableVector12(values: Array(repeating: 0, count: 12))
  }

  static func + (lhs: Self, rhs: Self) -> Self {
    AnimatableVector12(values: zip(lhs.values, rhs.values).map(+))
  }

  static func - (lhs: Self, rhs: Self) -> Self {
    AnimatableVector12(values: zip(lhs.values, rhs.values).map(-))
  }

  mutating func scale(by rhs: Double) {
    values = values.map { $0 * CGFloat(rhs) }
  }

  var magnitudeSquared: Double {
    values.reduce(0) { $0 + Double($1 * $1) }
  }
}

/// Three stroked lines in normalized 0..1 coordinates (x1,y1,x2,y2 per
/// line). SwiftUI tweens the coordinates through `animatableData`, so one
/// letter's strokes glide into the next letter's.
struct ModeGlyphShape: Shape {
  var vector: AnimatableVector12

  var animatableData: AnimatableVector12 {
    get { vector }
    set { vector = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let coords = vector.values
    for line in 0..<3 {
      let base = line * 4
      let start = CGPoint(
        x: rect.minX + coords[base] * rect.width,
        y: rect.minY + coords[base + 1] * rect.height
      )
      let end = CGPoint(
        x: rect.minX + coords[base + 2] * rect.width,
        y: rect.minY + coords[base + 3] * rect.height
      )
      guard start != end else { continue }
      path.move(to: start)
      path.addLine(to: end)
    }
    return path
  }
}

/// nvim-style mode badge in the Raycast T-button slot (trailing corner of
/// the bottom bar, 38pt slot probed from the live app): a keycap-chip
/// letter that MORPHS between N / I / V as the mode changes -- N's left
/// stem swings up into I's top serif, the diagonal straightens into the
/// stem, the right stem swings down into the bottom serif. Chrome matches
/// the actions-menu kbd chips (hollow rounded rect, hairline ring) and
/// the letter keeps the icon set's 1.5pt round-cap stroke, per David's
/// "fit the style/stroke of the icons" (2026-08-10). Overlaid on the
/// bottom bar, so it never contributes measured height; dims when the
/// panel resigns key.
struct VimModePill: View {
  @ObservedObject var controller: VimController
  let isKey: Bool

  /// N: left stem, diagonal, right stem.
  private static let nGlyph: [CGFloat] = [
    0.18, 0.88, 0.18, 0.12,
    0.18, 0.12, 0.82, 0.88,
    0.82, 0.88, 0.82, 0.12
  ]
  /// I: top serif, center stem, bottom serif.
  private static let iGlyph: [CGFloat] = [
    0.32, 0.12, 0.68, 0.12,
    0.50, 0.12, 0.50, 0.88,
    0.32, 0.88, 0.68, 0.88
  ]
  /// V: two legs; the third line collapses onto the right leg.
  private static let vGlyph: [CGFloat] = [
    0.18, 0.12, 0.50, 0.88,
    0.50, 0.88, 0.82, 0.12,
    0.50, 0.88, 0.82, 0.12
  ]

  var body: some View {
    ZStack {
      // A keycap, not a traffic light: the badge borrows the actions-menu
      // kbd chip chrome (hollow rounded rect, 1pt hairline ring, no fill)
      // so it reads as one family with the icons and shortcut chips; the
      // mode letter keeps the icon set's stroke weight (1.5pt round
      // caps). Color stays the only mode signal -- ring at a low tier
      // like the chips' fg-20 ring, letter at full tint.
      RoundedRectangle(cornerRadius: 5.5, style: .continuous)
        .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        .frame(width: 26, height: 26)
      ModeGlyphShape(vector: AnimatableVector12(values: glyph))
        .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        .frame(width: 13, height: 13)
    }
    .frame(width: 38, height: 38)
    .opacity(isKey ? 1 : 0.45)
    .animation(.spring(response: 0.17, dampingFraction: 0.72), value: controller.mode)
    .animation(.easeOut(duration: 0.12), value: isKey)
    .accessibilityLabel("Vim mode: \(modeName)")
  }

  private var glyph: [CGFloat] {
    switch controller.mode {
    case .insert: return Self.iGlyph
    case .normal: return Self.nGlyph
    case .visual, .visualLine: return Self.vGlyph
    }
  }

  private var modeName: String {
    switch controller.mode {
    case .insert: return "insert"
    case .normal: return "normal"
    case .visual: return "visual"
    case .visualLine: return "visual line"
    }
  }

  /// Insert is the probed Raycast caret red; normal the probed "Current"
  /// dot blue; visual a violet in the same saturation family as the blue
  /// (Raycast's own palette has no probed purple).
  private var tint: Color {
    switch controller.mode {
    case .insert: return Color(red: 0xEB / 255, green: 0x55 / 255, blue: 0x45 / 255)
    case .normal: return Color(red: 0x64 / 255, green: 0xA1 / 255, blue: 0xF1 / 255)
    case .visual, .visualLine: return Color(red: 0x9B / 255, green: 0x7C / 255, blue: 0xF2 / 255)
    }
  }
}
