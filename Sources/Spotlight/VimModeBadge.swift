import SwiftUI

/// nvim mode badge in the Raycast T-button slot (bottom bar trailing
/// corner). The treatment is Raycast's own circled-T button (David
/// 2026-08-11: "make the n/i thing in the places where raycast puts
/// the T in the circle"): a 38pt circle in the icon pill's solid fill
/// with its white-0.08 hairline ring, the mode letter set in the
/// chrome's Inter -- no custom glyph, no keycap chrome. Color stays
/// the only mode signal: insert = probed caret red, normal = probed
/// Current-dot blue, visual = family violet; the letter drops to the
/// resigned control tint when the panel is not key, like the top
/// pill's icons.
struct VimModeBadge: View {
  @ObservedObject var controller: VimController
  let isKey: Bool

  var body: some View {
    ZStack {
      Circle()
        .fill(RaycastChromePalette.pillFill)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
      Text(letter)
        .font(RaycastFont.medium(17))
        .foregroundStyle(isKey ? tint : RaycastChromePalette.controlResigned)
        .contentTransition(.opacity)
    }
    .frame(width: 38, height: 38)
    .animation(.spring(response: 0.17, dampingFraction: 0.72), value: controller.mode)
    .animation(.easeOut(duration: 0.12), value: isKey)
    .accessibilityLabel("Vim mode: \(modeName)")
  }

  private var letter: String {
    switch controller.mode {
    case .insert: return "I"
    case .normal: return "N"
    case .visual, .visualLine: return "V"
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
