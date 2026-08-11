import AppKit
import SwiftUI

/// The Raycast Notes actions modal (the ⌘ pill button): searchable list
/// of SpotNote commands (the `SpotNoteCommand` registry) with their
/// keycap shortcuts.
struct RaycastActionsModal: View {
  let actions: [SpotNoteCommand]
  let onClose: () -> Void
  @State private var query = ""
  @State private var selectedIndex = 0
  /// The command whose flyout submenu is open, and its lazily built
  /// model; the submenu rides a second child panel anchored to the row.
  @State private var openSubmenuID: String?
  @State private var openSubmenu: SpotNoteSubmenu?

  private var filtered: [SpotNoteCommand] {
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
          onMove: { move($0) },
          onRight: { openSelectedSubmenu() }
        )
        searchDivider
        list
      }
    }
    .onChange(of: query) { _, _ in
      selectedIndex = filtered.firstIndex(where: \.isEnabled) ?? 0
    }
  }

  private var list: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        let rows = filtered
        if rows.isEmpty {
          Text("No matching actions")
            .font(RaycastFont.regular(13))
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
      // Live menu: hairline to first row box is 5px at 2x, last row box
      // to sheet bottom 13.5px (2026-08-10); ours ran 14.5/32.5.
      .padding(.top, 2.5)
      .padding(.bottom, 7)
    }
    // The sheet HUGS its content like the live menu: a bare
    // `.frame(maxHeight:)` lets the greedy ScrollView take the full cap
    // even when rows need less (David's 2026-08-10 capture showed a
    // ~116pt empty tail). Rows are fixed-height, so the natural height
    // is exact. No cap: the unfiltered list IS the tallest case, and the
    // live menu shows its whole ~500pt list (a 400pt cap hid rows below
    // the fold in David's capture); the overhang panel already clamps
    // to the screen.
    .frame(height: listHeight)
  }

  /// Full-width hairline under the actions search field -- probed
  /// (49,50,62) over the (31,32,42) sheet on the live menu (2026-08-10).
  /// The browse modal draws the SAME rule (see RaycastNotesModal).
  private var searchDivider: some View {
    RaycastModalHairline()
  }

  /// Group gap: the live menu's row boxes sit 53px apart at 2x across a
  /// section break (26.5pt box-to-box; 2026-08-10 native capture). With
  /// rows now touching, the spacer carries the whole gap -- the earlier
  /// 17pt + 2x4pt row spacing summed to 50px.
  private static let sectionGapHeight: CGFloat = 26.5

  private var listHeight: CGFloat {
    let rows = filtered
    guard !rows.isEmpty else { return 70 }
    let gaps = zip(rows, rows.dropFirst()).filter { $0.section != $1.section }.count
    let content =
      CGFloat(rows.count) * RaycastModalPalette.rowHeight
      + CGFloat(gaps) * Self.sectionGapHeight
    return content + 2.5 + 7
  }

  /// Group gap with Raycast's separator rule centered in it: a row-mean
  /// luminance scan across the live gap (2026-08-10) found a single-row
  /// hairline at (48,49,62) over the (30,31,42) sheet -- white at ~0.08,
  /// same weight as the search-field rule. (The earlier "pure gap" call
  /// came from a coarser threshold scan that missed a 1px line; do not
  /// re-delete it.)
  private var sectionGap: some View {
    Color.clear.frame(height: Self.sectionGapHeight)
      .overlay(RaycastModalHairline())
  }

  private func row(_ action: SpotNoteCommand, index: Int) -> some View {
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
          .font(RaycastFont.regular(16))
          .foregroundStyle(RaycastModalPalette.primaryText)
        Spacer(minLength: 12)
        keycaps(action.keys)
      }
      .opacity(action.isEnabled ? 1 : RaycastModalPalette.disabledOpacity)
      // 9.5pt leading compensates the 9.5pt rowInset (icon ink keeps its
      // screen position); trailing 10pt rests the chip ring 39px from
      // the sheet edge at 2x like the live menu (round-12 capture --
      // the old 8.5 sat it at 36).
      .padding(.leading, 9.5)
      .padding(.trailing, 10)
      .frame(height: RaycastModalPalette.rowHeight)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: RaycastModalPalette.rowCornerRadius, style: .continuous)
          .fill(isSelected ? RaycastModalPalette.selectedRow : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Raycast's highlight FOLLOWS the pointer (their live menu hovers a
    // row and it lights without a click); the highlight stays on the
    // last hovered row when the pointer leaves, like theirs.
    .onHover { inside in
      if inside, action.isEnabled {
        selectedIndex = index
      }
    }
    // The invoking row anchors its flyout: the presenter reads this
    // background view's frame so the submenu header lands on the row.
    .background { submenuAnchor(for: action) }
  }

  @ViewBuilder
  private func submenuAnchor(for action: SpotNoteCommand) -> some View {
    if action.id == openSubmenuID, let model = openSubmenu {
      RaycastSubmenuOverhang(
        model: model,
        onCommit: { command in
          closeSubmenu()
          onClose()
          command.perform()
        },
        onClose: { closeSubmenu() },
        onDismissAll: {
          closeSubmenu()
          onClose()
        }
      )
    }
  }

  private func closeSubmenu() {
    openSubmenu = nil
    openSubmenuID = nil
  }

  /// → on a row with a submenu opens it (only while the query is empty
  /// -- with text in the field the arrow stays a caret move); Enter
  /// opens it regardless via `commit`.
  private func openSelectedSubmenu() -> Bool {
    guard query.isEmpty else { return false }
    let rows = filtered
    guard rows.indices.contains(selectedIndex),
      let provider = rows[selectedIndex].submenu,
      rows[selectedIndex].isEnabled
    else { return false }
    openSubmenuID = rows[selectedIndex].id
    openSubmenu = provider()
    return true
  }

  /// Rasters preloaded once; actions rebuild on every body evaluation.
  private static let rasters: [String: NSImage] = Dictionary(
    uniqueKeysWithValues: [
      "RaycastPlus", "RaycastTextSearch", "RaycastCopyClipboard", "RaycastSwatch"
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
      RaycastStackedCardsIcon(scale: 0.845)
    case .swatch(let color):
      RaycastSwatchDot(color: color)
    }
  }

  @ViewBuilder
  private func keycaps(_ keys: [String]) -> some View {
    if !keys.isEmpty {
      // Raycast's kbd chips are HOLLOW: their stylesheet gives
      // `[data-variant=default]` a transparent background under a 1px
      // inset ring of fg-20, glyph in fg-60 -- the live chip interior
      // probes exactly the sheet color, and our earlier white-0.05
      // "physical key" fill is what read different. Radius ~4.5pt and a
      // 2.5pt gap (5px at 2x between chip outlines).
      HStack(spacing: 2.5) {
        ForEach(keys, id: \.self) { key in
          Text(key)
            .font(RaycastFont.medium(13))
            .foregroundStyle(RaycastModalPalette.secondaryInk)
            .frame(minWidth: 22)
            .frame(height: 22)
            .background(
              RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(RaycastModalPalette.borderInk, lineWidth: 1)
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
    if let provider = action.submenu {
      openSubmenuID = action.id
      openSubmenu = provider()
      return
    }
    onClose()
    action.perform()
  }
}
