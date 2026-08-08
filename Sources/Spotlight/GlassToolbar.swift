import SwiftUI

/// Top HUD chrome: circular controls flanking a segmented formatting pill,
/// in the macOS 26 Liquid Glass capture-panel layout. Controls use subtle
/// translucent fills rather than nested `glassEffect` shapes — the panel
/// itself is the glass surface, and Apple's guidance is not to stack glass
/// on glass.
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

  private static let controlDiameter: CGFloat = 34
  private static let segmentWidth: CGFloat = 44

  private var controlFill: Color {
    theme.mode == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
  }

  var body: some View {
    HStack(spacing: 10) {
      circleButton("xmark", help: "Close", action: onClose)
      circleButton("doc", help: "Switch note", action: onOpenNotes)
      circleButton(isPinned ? "pin.fill" : "pin", help: "Stay fully visible", action: onTogglePin)
      Spacer(minLength: 0)
      formatPill
      Spacer(minLength: 0)
      circleButton("number", help: "Find in note", action: onToggleFind)
    }
    .padding(.horizontal, 14)
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
    .overlay(Capsule(style: .continuous).strokeBorder(theme.border, lineWidth: 1))
  }

  private var pillDivider: some View {
    Rectangle()
      .fill(theme.border)
      .frame(width: 1, height: Self.controlDiameter - 14)
  }

  private func circleButton(
    _ systemName: String,
    help: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(theme.text)
        .frame(width: Self.controlDiameter, height: Self.controlDiameter)
        .background(Circle().fill(controlFill))
        .overlay(Circle().strokeBorder(theme.border, lineWidth: 1))
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
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(emphasized ? theme.headingText : theme.text)
        .frame(width: Self.segmentWidth, height: Self.controlDiameter)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}
