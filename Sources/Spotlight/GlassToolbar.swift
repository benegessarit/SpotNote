import SwiftUI

/// Top HUD chrome in the SlashNote capture-panel layout, built from native
/// macOS 26 components: Liquid Glass button styles over the glass card, SF
/// Symbols, and semantic label colors — no hand-rolled fills. Left cluster
/// close/notes/pin; right cluster the segmented formatting pill plus the
/// tag/find circle.
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
    .glassEffect()
  }

  private var pillDivider: some View {
    Rectangle()
      .fill(.separator)
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
        .foregroundStyle(.secondary)
        .frame(width: Self.controlDiameter, height: Self.controlDiameter)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
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
        .foregroundStyle(emphasized ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .frame(width: Self.segmentWidth, height: Self.controlDiameter)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}
