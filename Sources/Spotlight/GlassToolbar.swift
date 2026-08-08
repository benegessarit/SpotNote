import SwiftUI

/// Top HUD chrome in the SlashNote capture-panel layout: small circular
/// controls on the left (close, notes, pin), and a right cluster holding the
/// segmented formatting pill plus the tag/find circle. Sizing and alpha values
/// come from the SlashNote site demo CSS (24px circles, white 8% fills,
/// white 50% glyphs) — controls use flat translucent fills, not nested glass;
/// the panel itself is the glass surface.
struct GlassToolbar: View {
  let theme: Theme
  let isPinned: Bool
  let showsLineNumbers: Bool
  let onClose: () -> Void
  let onOpenNotes: () -> Void
  let onTogglePin: () -> Void
  let onCycleTheme: () -> Void
  let onInsertBullet: () -> Void
  let onToggleLineNumbers: () -> Void
  let onToggleFind: () -> Void

  private static let controlDiameter: CGFloat = 24
  private static let segmentWidth: CGFloat = 30

  private var controlFill: Color {
    theme.mode == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
  }

  private var glyphColor: Color {
    theme.text.opacity(0.60)
  }

  var body: some View {
    HStack(spacing: 6) {
      circleButton("xmark", help: "Close", action: onClose)
      circleButton("doc", help: "Switch note", action: onOpenNotes)
      circleButton(isPinned ? "pin.fill" : "pin", help: "Stay fully visible", action: onTogglePin)
      Spacer(minLength: 0)
      formatPill
      circleButton("number", help: "Find in note", action: onToggleFind)
    }
    .padding(.horizontal, 10)
    .frame(height: EditorMetrics.toolbarHeight)
  }

  private var formatPill: some View {
    HStack(spacing: 0) {
      pillSegment("textformat.size", help: "Cycle theme", action: onCycleTheme)
      pillDivider
      pillSegment("checklist", help: "New bullet", action: onInsertBullet)
      pillDivider
      pillSegment(
        "list.number",
        emphasized: showsLineNumbers,
        help: "Line numbers",
        action: onToggleLineNumbers
      )
    }
    .background(Capsule(style: .continuous).fill(controlFill))
  }

  private var pillDivider: some View {
    Rectangle()
      .fill(theme.border)
      .frame(width: 1, height: 12)
  }

  private func circleButton(
    _ systemName: String,
    help: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(glyphColor)
        .frame(width: Self.controlDiameter, height: Self.controlDiameter)
        .background(Circle().fill(controlFill))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private func pillSegment(
    _ systemName: String,
    emphasized: Bool = false,
    help: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(emphasized ? theme.text : glyphColor)
        .frame(width: Self.segmentWidth, height: Self.controlDiameter)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}
