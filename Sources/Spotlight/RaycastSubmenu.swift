import SwiftUI

/// Metrics for the Raycast flyout submenu, pixel-probed from David's
/// Raycast AI "Change Model…" capture (2x, 2026-08-11) cross-checked
/// against Raycast's shipped popover stylesheet (`popover-DXQ3FJok.css`):
/// the sheet is 838px wide at 2x, rows ride the same 86px pitch as the
/// actions menu, and items are the LARGE size (padding-inline 16,
/// icon-22, gap-12) -- the icon-frame model lands the measured title
/// ink at x=1148 exactly. Header, section captions, and accessories all
/// share one secondary tone (fg-60) at a 20.5pt text inset; the search
/// field sits at the BOTTOM (their upwardsLayout) under a hairline that
/// spans only the content width (21pt side insets -- unlike the Notes
/// modals' edge-to-edge rule). The capture is cropped at the sheet
/// bottom, so the search-zone height is center-derived (53.5pt) and
/// flagged, not probed.
enum RaycastSubmenuMetrics {
  static let width: CGFloat = 419
  /// Sheet top to the first row's top (75.5px): the dimmed parent-title
  /// header zone, its text cap 18pt below the sheet top.
  static let headerHeight: CGFloat = 37.75
  static let headerTextTopPad: CGFloat = 14
  /// Header/section-caption/accessory text inset from the sheet edge
  /// (41px at 2x).
  static let textInset: CGFloat = 20.5
  /// Row icon frame's inset from the sheet edge (32px) -- the CSS
  /// padding-inline: 16 of the large item size.
  static let contentInset: CGFloat = 16
  static let iconFrame: CGFloat = 22
  static let iconGap: CGFloat = 12
  /// Accessory ink's inset from the right sheet edge (40px).
  static let trailingInset: CGFloat = 20
  /// Chip pill -> accessory text gap: 45px in the capture (chip ends
  /// x=1684, "Raycast" ink starts 1729) -- NOT the stylesheet's 8/12
  /// accessory gap; the rendered pill carries its own margin.
  static let chipGap: CGFloat = 22.5
  /// Section break, row-bottom to next-row-top (97.5px): 10.5pt gap,
  /// the fade rule, 18pt to the caption's cap, caption, 8pt to rows.
  static let sectionBreakHeight: CGFloat = 48.75
  static let sectionGapAboveRule: CGFloat = 10.5
  static let sectionTextBottomPad: CGFloat = 8
  /// A titled FIRST section has no separator: the full break minus the
  /// gap-above-rule and the rule itself (48.75 - 10.5 - 0.5). Not in
  /// the capture (its first group is untitled) -- re-probe when a
  /// capture with a titled first section exists.
  static let firstSectionTitleHeight: CGFloat = 37.75
  /// Untitled mid-list break: the actions modal's probed group gap.
  static let untitledBreakHeight: CGFloat = 26.5
  static let searchHeight: CGFloat = 53.5
  /// Search hairline side insets (42-43px at 2x).
  static let hairlineInset: CGFloat = 21
  /// Keyboard/current selection fills selection-10 -- twice the Notes
  /// menus' hover tone; pointer hover stays selection-5 (their
  /// stylesheet keeps the two states distinct in submenus).
  static let selectedFill = RaycastModalPalette.primaryText.opacity(0.10)
}

/// The flyout submenu: dimmed parent-title header, titled sections of
/// large rows, search at the bottom. Keyboard: ↑/↓ move (wrapping,
/// skipping disabled), Enter commits, Esc -- and ← on an empty query --
/// return to the parent menu. Pointer hover lights rows separately from
/// the keyboard selection and a click commits.
struct RaycastSubmenu: View {
  let model: SpotNoteSubmenu
  /// Cap for the row list; the presenter derives it from the screen.
  var maxListHeight: CGFloat = .infinity
  let onCommit: (SpotNoteCommand) -> Void
  let onClose: () -> Void

  @State private var query = ""
  @State private var selectedID: String?
  @State private var hoveredID: String?

  private var sections: [SpotNoteSubmenuSection] { model.filtered(query: query) }
  private var flatItems: [SpotNoteCommand] { sections.flatMap(\.items) }

  var body: some View {
    RaycastModalSheet(width: RaycastSubmenuMetrics.width) {
      VStack(alignment: .leading, spacing: 0) {
        header
        list
        searchZone
      }
    }
    .onAppear {
      selectedID = model.defaultSelectedID ?? SubmenuSelection.firstEnabled(in: flatItems)
    }
    .onChange(of: query) { _, _ in
      selectedID = SubmenuSelection.firstEnabled(in: flatItems)
    }
  }

  /// The invoking command's title as a dimmed, non-selectable header
  /// row; clicking it goes back to the parent, like closing the flyout.
  private var header: some View {
    Text(model.title)
      .font(RaycastFont.regular(16))
      .foregroundStyle(RaycastModalPalette.secondaryText)
      .padding(.leading, RaycastSubmenuMetrics.textInset)
      .padding(.top, RaycastSubmenuMetrics.headerTextTopPad)
      .frame(
        maxWidth: .infinity,
        minHeight: RaycastSubmenuMetrics.headerHeight,
        maxHeight: RaycastSubmenuMetrics.headerHeight,
        alignment: .topLeading
      )
      .contentShape(Rectangle())
      .onTapGesture(perform: onClose)
  }

  private var list: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
            sectionBreak(section, isFirst: index == 0)
            ForEach(section.items) { item in
              row(item)
                .id(item.id)
            }
          }
          if flatItems.isEmpty {
            Text("No matches")
              .font(RaycastFont.regular(13))
              .foregroundStyle(RaycastModalPalette.secondaryText)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 20)
          }
        }
        .padding(.horizontal, RaycastModalPalette.rowInset)
      }
      .frame(height: listHeight)
      .onChange(of: selectedID) { _, id in
        // Hover never writes selectedID here, so every change is a
        // keyboard move: keep it visible.
        guard let id else { return }
        withAnimation(.easeOut(duration: 0.16)) {
          proxy.scrollTo(id, anchor: .center)
        }
      }
    }
  }

  private var listHeight: CGFloat {
    min(Self.naturalListHeight(for: sections), maxListHeight)
  }

  /// Row-list height for a section set -- shared with the presenter's
  /// panel sizing so the sheet hugs its content exactly.
  static func naturalListHeight(for sections: [SpotNoteSubmenuSection]) -> CGFloat {
    guard !sections.isEmpty else { return 60 }
    var total: CGFloat = 0
    for (index, section) in sections.enumerated() {
      total += breakHeight(for: section, isFirst: index == 0)
      total += CGFloat(section.items.count) * RaycastModalPalette.rowHeight
    }
    return total
  }

  /// Full sheet height for the presenter's panel frame.
  static func sheetHeight(for model: SpotNoteSubmenu, maxListHeight: CGFloat) -> CGFloat {
    RaycastSubmenuMetrics.headerHeight
      + min(naturalListHeight(for: model.sections), maxListHeight)
      + RaycastSubmenuMetrics.searchHeight
  }

  private static func breakHeight(for section: SpotNoteSubmenuSection, isFirst: Bool) -> CGFloat {
    if isFirst {
      return section.title == nil ? 0 : RaycastSubmenuMetrics.firstSectionTitleHeight
    }
    return section.title == nil
      ? RaycastSubmenuMetrics.untitledBreakHeight
      : RaycastSubmenuMetrics.sectionBreakHeight
  }

  @ViewBuilder
  private func sectionBreak(_ section: SpotNoteSubmenuSection, isFirst: Bool) -> some View {
    let height = Self.breakHeight(for: section, isFirst: isFirst)
    if height > 0 {
      Color.clear
        .frame(height: height)
        .overlay(alignment: .top) {
          if !isFirst {
            RaycastSubmenuFadeRule()
              .padding(.top, RaycastSubmenuMetrics.sectionGapAboveRule)
          }
        }
        .overlay(alignment: .bottomLeading) {
          if let title = section.title {
            Text(title)
              .font(RaycastFont.medium(13))
              .foregroundStyle(RaycastModalPalette.secondaryText)
              // 11 = the 20.5pt text inset minus the 9.5pt row inset.
              .padding(.leading, RaycastSubmenuMetrics.textInset - RaycastModalPalette.rowInset)
              .padding(.bottom, RaycastSubmenuMetrics.sectionTextBottomPad)
          }
        }
    }
  }

  private func row(_ item: SpotNoteCommand) -> some View {
    Button {
      guard item.isEnabled else { return }
      onCommit(item)
    } label: {
      rowLabel(item)
    }
    .buttonStyle(.plain)
    .onHover { inside in
      hoveredID = inside ? item.id : (hoveredID == item.id ? nil : hoveredID)
    }
  }

  private func rowLabel(_ item: SpotNoteCommand) -> some View {
    HStack(spacing: 0) {
      iconView(item.icon)
        .foregroundStyle(RaycastModalPalette.primaryText)
        .frame(
          width: RaycastSubmenuMetrics.iconFrame,
          height: RaycastSubmenuMetrics.iconFrame
        )
      Spacer().frame(width: RaycastSubmenuMetrics.iconGap)
      Text(item.title)
        .font(RaycastFont.regular(16))
        .foregroundStyle(RaycastModalPalette.primaryText)
        .lineLimit(1)
      Spacer(minLength: 12)
      if let chip = item.chip {
        RaycastBetaChip(text: chip)
        Spacer().frame(width: RaycastSubmenuMetrics.chipGap)
      }
      if let trailing = item.trailing {
        Text(trailing)
          .font(RaycastFont.regular(16))
          .foregroundStyle(RaycastModalPalette.secondaryText)
          .lineLimit(1)
      }
    }
    .opacity(item.isEnabled ? 1 : RaycastModalPalette.disabledOpacity)
    // Insets compensate the 9.5pt highlight inset: icon frame lands
    // 16pt and accessory ink 20pt from the sheet edges, per the probes.
    .padding(.leading, RaycastSubmenuMetrics.contentInset - RaycastModalPalette.rowInset)
    .padding(.trailing, RaycastSubmenuMetrics.trailingInset - RaycastModalPalette.rowInset)
    .frame(height: RaycastModalPalette.rowHeight)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: RaycastModalPalette.rowCornerRadius, style: .continuous)
        .fill(rowFill(item))
    )
    .contentShape(Rectangle())
  }

  private func rowFill(_ item: SpotNoteCommand) -> Color {
    if item.id == selectedID { return RaycastSubmenuMetrics.selectedFill }
    if item.id == hoveredID, item.isEnabled { return RaycastModalPalette.selectedRow }
    return Color.clear
  }

  @ViewBuilder
  private func iconView(_ icon: RaycastActionIcon) -> some View {
    switch icon {
    case .raster(let resource, let frame):
      Image(nsImage: raycastIconImage(resource))
        .renderingMode(.template)
        .resizable()
        .frame(width: frame, height: frame)
    case .stackedCards:
      RaycastStackedCardsIcon(scale: 0.845)
    case .swatch(let color):
      RaycastSwatchDot(color: color)
    }
  }

  /// Hairline + field sum to exactly `searchHeight`, so the static
  /// sheet-height math stays honest.
  private var searchZone: some View {
    VStack(spacing: 0) {
      RaycastModalHairline()
        .padding(.horizontal, RaycastSubmenuMetrics.hairlineInset)
      RaycastSubmenuSearchField(
        placeholder: model.searchPlaceholder,
        showsInfoButton: model.showsInfoButton,
        text: $query,
        onSubmit: { commitSelection() },
        onEscape: onClose,
        onMove: { delta in
          selectedID = SubmenuSelection.move(from: selectedID, by: delta, in: flatItems)
        },
        onBack: onClose
      )
    }
  }

  private func commitSelection() {
    guard let item = flatItems.first(where: { $0.id == selectedID }), item.isEnabled else {
      return
    }
    onCommit(item)
  }
}

/// The submenu's group separator: a 0.5pt fg-10 rule whose ends fade
/// out -- Raycast's macOS stylesheet masks its separators transparent
/// at the edges (ink from 10% to 90%). The gradient IS the fill: a
/// `.mask` on a half-point-high layer rasterizes to nothing headless
/// (verified 2026-08-11), and the direct gradient fill is equivalent.
struct RaycastSubmenuFadeRule: View {
  var body: some View {
    Rectangle()
      .fill(
        LinearGradient(
          stops: [
            .init(color: RaycastModalPalette.hairlineInk.opacity(0), location: 0),
            .init(color: RaycastModalPalette.hairlineInk, location: 0.1),
            .init(color: RaycastModalPalette.hairlineInk, location: 0.9),
            .init(color: RaycastModalPalette.hairlineInk.opacity(0), location: 1)
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .frame(height: 0.5)
  }
}

/// The yellow "Beta" pill from the capture: 26.5x10pt, bright
/// (245,227,181) fill with near-black text -- the capture's rendered
/// chip, which beats the stylesheet's yellow-on-yellow-10 variant guess.
struct RaycastBetaChip: View {
  let text: String

  var body: some View {
    Text(text)
      .font(RaycastFont.medium(9))
      .foregroundStyle(Color(red: 51 / 255, green: 49 / 255, blue: 52 / 255))
      .padding(.horizontal, 3.25)
      .frame(height: 10)
      .background(
        Capsule().fill(Color(red: 245 / 255, green: 227 / 255, blue: 181 / 255))
      )
  }
}

/// Bottom search field (upwardsLayout): same field styling as the top
/// modals, taller zone, optional ⓘ accessory, and ← on an empty query
/// walks back to the parent menu.
private struct RaycastSubmenuSearchField: View {
  let placeholder: String
  let showsInfoButton: Bool
  @Binding var text: String
  var onSubmit: () -> Void
  var onEscape: () -> Void
  var onMove: (Int) -> Void
  var onBack: () -> Void
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 0) {
      ZStack(alignment: .leading) {
        if text.isEmpty {
          Text(placeholder)
            .font(RaycastFont.regular(16))
            .foregroundStyle(RaycastModalPalette.searchPlaceholder)
            .allowsHitTesting(false)
        }
        field
      }
      if showsInfoButton {
        Image(systemName: "info.circle")
          .font(.system(size: 16))
          .foregroundStyle(RaycastModalPalette.secondaryInk)
      }
    }
    .padding(.leading, 20)
    .padding(.trailing, 15.75)
    .frame(height: RaycastSubmenuMetrics.searchHeight - 0.5)
    .onAppear { focused = true }
  }

  private var field: some View {
    TextField("", text: $text)
      .textFieldStyle(.plain)
      .font(RaycastFont.regular(16))
      .foregroundStyle(RaycastModalPalette.primaryText)
      .tint(RaycastModalPalette.primaryText)
      .focused($focused)
      .onSubmit(onSubmit)
      .onKeyPress(.escape) {
        onEscape()
        return .handled
      }
      .onKeyPress(.upArrow) {
        onMove(-1)
        return .handled
      }
      .onKeyPress(.downArrow) {
        onMove(+1)
        return .handled
      }
      .onKeyPress(.leftArrow) {
        guard text.isEmpty else { return .ignored }
        onBack()
        return .handled
      }
      .onKeyPress(.init("w"), phases: .down) { press in
        guard press.modifiers.contains(.control) else { return .ignored }
        text = SearchTextEditing.deleteWordBackward(text)
        return .handled
      }
  }
}
