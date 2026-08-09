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

/// nvim-style mode badge in the bottom bar's leading corner: a rounded
/// square whose letter MORPHS between N / I / V as the mode changes --
/// N's left stem swings up into I's top serif, the diagonal straightens
/// into the stem, the right stem swings down into the bottom serif.
/// Overlaid on the bottom bar, so it never contributes measured height;
/// dims when the panel resigns key, like the rest of the chrome.
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
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(tint.opacity(0.16))
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
      ModeGlyphShape(vector: AnimatableVector12(values: glyph))
        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: 11, height: 11)
    }
    .frame(width: 22, height: 22)
    .opacity(isKey ? 1 : 0.45)
    .animation(.spring(response: 0.4, dampingFraction: 0.72), value: controller.mode)
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

  /// Insert is the caret red; normal the Raycast "Current" blue; visual
  /// modes purple.
  private var tint: Color {
    switch controller.mode {
    case .insert: return Color(red: 0xEB / 255, green: 0x55 / 255, blue: 0x45 / 255)
    case .normal: return Color(red: 0x64 / 255, green: 0xA1 / 255, blue: 0xF1 / 255)
    case .visual, .visualLine: return Color(red: 0xBD / 255, green: 0x93 / 255, blue: 0xF9 / 255)
    }
  }
}
