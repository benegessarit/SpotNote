import SwiftUI

/// nvim-style mode indicator in the bottom bar's leading corner: rests as
/// a small caret-red dot while typing (insert) and spring-morphs into a
/// labeled capsule in normal/visual mode -- the Dynamic Island-style
/// dot-to-pill microinteraction from David's component picks. Overlaid on
/// the bottom bar, so it never contributes measured height, and hidden
/// with the rest of the chrome when the panel resigns key.
struct VimModePill: View {
  @ObservedObject var controller: VimController
  let isKey: Bool

  var body: some View {
    ZStack {
      Capsule(style: .continuous)
        .fill(fill)
        .overlay(Capsule(style: .continuous).strokeBorder(stroke, lineWidth: 1))
      Text(label)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .tracking(0.8)
        .foregroundStyle(tint)
        .opacity(expanded ? 1 : 0)
        .scaleEffect(expanded ? 1 : 0.4)
    }
    .frame(width: width, height: height)
    .opacity(isKey ? 1 : 0)
    .animation(.spring(response: 0.35, dampingFraction: 0.72), value: controller.mode)
    .animation(.easeOut(duration: 0.12), value: isKey)
    .accessibilityLabel("Vim mode: \(expanded ? label : "INSERT")")
  }

  private var expanded: Bool { controller.mode != .insert }

  private var width: CGFloat {
    switch controller.mode {
    case .insert: return 7
    case .normal: return 68
    case .visual: return 64
    case .visualLine: return 62
    }
  }

  private var height: CGFloat { expanded ? 20 : 7 }

  private var label: String {
    switch controller.mode {
    case .insert: return ""
    case .normal: return "NORMAL"
    case .visual: return "VISUAL"
    case .visualLine: return "V-LINE"
    }
  }

  /// Insert rests as the caret red; normal is the Raycast "Current" blue;
  /// visual modes go purple.
  private var tint: Color {
    switch controller.mode {
    case .insert: return Color(red: 0xEB / 255, green: 0x55 / 255, blue: 0x45 / 255)
    case .normal: return Color(red: 0x64 / 255, green: 0xA1 / 255, blue: 0xF1 / 255)
    case .visual, .visualLine: return Color(red: 0xBD / 255, green: 0x93 / 255, blue: 0xF9 / 255)
    }
  }

  private var fill: Color { expanded ? tint.opacity(0.16) : tint }
  private var stroke: Color { expanded ? tint.opacity(0.45) : .clear }
}
