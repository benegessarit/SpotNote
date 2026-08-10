import AppKit
import SwiftUI

/// Row glyph in the actions modal: an exact @raycast/icons raster (frame
/// tuned per asset so visible glyphs match the probed ~12.5pt), or the
/// custom fanned-cards note-switcher.
enum RaycastActionIcon {
  case raster(resource: String, frame: CGFloat)
  case stackedCards
}

/// One entry in the Raycast-style actions modal.
struct RaycastAction: Identifiable {
  let id: String
  let title: String
  let icon: RaycastActionIcon
  /// Display keycaps, e.g. ["⌘", "N"]. Empty = no shortcut shown.
  let keys: [String]
  /// Spacing group; a wide pure-whitespace gap renders between groups.
  let section: Int
  /// Inapplicable actions stay listed but dim and can't be selected,
  /// like the live menu's greyed rows.
  var isEnabled: Bool = true
  let perform: () -> Void
}

/// The Raycast Notes actions modal (the ⌘ pill button): searchable list of
/// real SpotNote actions with their keycap shortcuts.
struct RaycastActionsModal: View {
  let actions: [RaycastAction]
  let onClose: () -> Void
  @State private var query = ""
  @State private var selectedIndex = 0

  private var filtered: [RaycastAction] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return actions }
    return actions.filter { $0.title.lowercased().contains(needle) }
  }

  var body: some View {
    RaycastModalSheet {
      VStack(alignment: .leading, spacing: 0) {
        RaycastModalSearchField(
          placeholder: "Search for actions...",
          text: $query,
          onSubmit: { commit() },
          onEscape: onClose,
          onMove: { move($0) }
        )
        searchDivider
        list
      }
      .padding(.bottom, 8)
    }
    .onChange(of: query) { _, _ in
      selectedIndex = filtered.firstIndex(where: \.isEnabled) ?? 0
    }
  }

  private var list: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: RaycastModalPalette.rowSpacing) {
        let rows = filtered
        if rows.isEmpty {
          Text("No matching actions")
            .font(.system(size: 13))
            .foregroundStyle(RaycastModalPalette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
        } else {
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, action in
            if index > 0, action.section != rows[index - 1].section {
              sectionGap
            }
            row(action, index: index)
          }
        }
      }
      .padding(.horizontal, RaycastModalPalette.rowInset)
      .padding(.top, 6)
      .padding(.bottom, 8)
    }
    // The sheet HUGS its content like the live menu: a bare
    // `.frame(maxHeight:)` lets the greedy ScrollView take the full cap
    // even when rows need less (David's 2026-08-10 capture showed a
    // ~116pt empty tail). Rows are fixed-height, so the natural height
    // is exact; only overflow scrolls.
    .frame(height: min(400, listHeight))
  }

  /// Full-width hairline under the actions search field -- probed
  /// (49,50,62) over the (31,32,42) sheet on the live menu (2026-08-10).
  /// The browse modal has NO such rule (its "Notes" header separates).
  private var searchDivider: some View {
    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
  }

  private static let sectionGapHeight: CGFloat = 25

  private var listHeight: CGFloat {
    let rows = filtered
    guard !rows.isEmpty else { return 70 }
    let gaps = zip(rows, rows.dropFirst()).filter { $0.section != $1.section }.count
    let content =
      CGFloat(rows.count) * RaycastModalPalette.rowHeight
      + CGFloat(gaps) * Self.sectionGapHeight
      + CGFloat(rows.count + gaps - 1) * RaycastModalPalette.rowSpacing
    return content + 6 + 8
  }

  /// Pure whitespace between action groups -- the live menu draws NO
  /// hairline (threshold scans across the gap found nothing, 2026-08-09;
  /// the earlier "rule probed" came from dim-polluted captures).
  private var sectionGap: some View {
    Color.clear.frame(height: Self.sectionGapHeight)
  }

  private func row(_ action: RaycastAction, index: Int) -> some View {
    let isSelected = index == selectedIndex && action.isEnabled
    return Button {
      guard action.isEnabled else { return }
      selectedIndex = index
      commit()
    } label: {
      HStack(spacing: 0) {
        // Icons share the PRIMARY text color -- the live rows read as one
        // bright unit (icon probes (207,214,241), same as the title).
        iconView(action.icon)
          .foregroundStyle(RaycastModalPalette.primaryText)
          .frame(width: 20, height: 20)
        Spacer().frame(width: 11)
        Text(action.title)
          .font(.system(size: 16))
          .foregroundStyle(RaycastModalPalette.primaryText)
        Spacer(minLength: 12)
        keycaps(action.keys)
      }
      .opacity(action.isEnabled ? 1 : RaycastModalPalette.disabledOpacity)
      .padding(.leading, 13)
      .padding(.trailing, 12)
      .frame(height: RaycastModalPalette.rowHeight)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: RaycastModalPalette.rowCornerRadius, style: .continuous)
          .fill(isSelected ? RaycastModalPalette.selectedRow : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// Rasters preloaded once; actions rebuild on every body evaluation.
  private static let rasters: [String: NSImage] = Dictionary(
    uniqueKeysWithValues: [
      "RaycastPlus", "RaycastMagnifyingGlass", "RaycastCopyClipboard",
      "RaycastSidebarLeft", "RaycastSwatch"
    ].map { ($0, raycastIconImage($0)) }
  )

  @ViewBuilder
  private func iconView(_ icon: RaycastActionIcon) -> some View {
    switch icon {
    case .raster(let resource, let frame):
      Image(nsImage: Self.rasters[resource] ?? raycastIconImage(resource))
        .renderingMode(.template)
        .resizable()
        .frame(width: frame, height: frame)
    case .stackedCards:
      RaycastStackedCardsIcon(scale: 0.77)
    }
  }

  @ViewBuilder
  private func keycaps(_ keys: [String]) -> some View {
    if !keys.isEmpty {
      HStack(spacing: 3) {
        ForEach(keys, id: \.self) { key in
          Text(key)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(RaycastModalPalette.secondaryText)
            .frame(minWidth: 22)
            .frame(height: 22)
            .background(
              // Physical-key look: a subtle interior fill a step lighter
              // than the sheet under the brighter border (live chip
              // corners probe ~(40,40,50)).
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                  RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
            )
        }
      }
    }
  }

  /// Arrow keys skip disabled rows (wrapping); with nothing enabled the
  /// selection stays put.
  private func move(_ delta: Int) {
    let rows = filtered
    let count = rows.count
    guard count > 0 else { return }
    var index = selectedIndex
    for _ in 0..<count {
      index = (index + delta + count) % count
      if rows[index].isEnabled {
        selectedIndex = index
        return
      }
    }
  }

  private func commit() {
    let rows = filtered
    guard rows.indices.contains(selectedIndex) else { return }
    let action = rows[selectedIndex]
    guard action.isEnabled else { return }
    onClose()
    action.perform()
  }
}
