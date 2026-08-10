import Core
import SwiftUI

/// Raycast's chrome/menu typeface is INTER, not SF -- the live app ships
/// `InterVariable.woff2` in its frontend bundle and every menu/title/chip
/// renders with it (same cap heights as SF at these sizes, ~2% wider,
/// visibly different letterforms). Bundled static instances registered by
/// `FontLoader`; SwiftUI `.custom` falls back silently, so the exact
/// PostScript names matter ("Inter-Regular"/"Inter-Medium").
enum RaycastFont {
  static func regular(_ size: CGFloat) -> Font {
    .custom("Inter-Regular", size: size)
  }
  static func medium(_ size: CGFloat) -> Font {
    .custom("Inter-Medium", size: size)
  }
}

/// Palette for the Raycast Notes floating modals (Browse Notes, Actions).
/// Pixel-sampled from the live Raycast Beta Notes modals: the sheet is
/// DARKER than the note surface, with a soft hover row and muted metadata.
enum RaycastModalPalette {
  /// The sheet is a translucent MATERIAL, not opaque paint: the live
  /// Raycast sheet transmits ~21% of the blurred backdrop (a blue chat
  /// row behind it lifts B by 43/200 of the raw delta) and DARKENS red
  /// (tR ~ -0.19, a desaturating material). Swatch-lab sweeps of
  /// (material x tint) against uniform blue/dark backdrops (2026-08-09)
  /// matched that signature with `.popover` at 0.45. A 0.90 tint (the
  /// first attempt) matched composite but killed the bleed (t ~ 0.02) --
  /// do not raise the tint to chase flat color. Ink corrected 2026-08-10
  /// from David's SAME-DESK side-by-side: our composite ran (+6,+5,+7)
  /// brighter than the live sheet ((37,38,49) vs (31,33,42)); dividing
  /// by the 0.45 tint puts the delta in the ink, keeping transmission.
  static let sheet = Color(red: 0x10 / 255, green: 0x12 / 255, blue: 0x19 / 255)
  static let sheetTintOpacity: CGFloat = 0.45
  /// Selected/hovered row: the live hovered rows probe (40,40,52) in the
  /// actions menu and (38,38,50) in browse (2026-08-10 native captures --
  /// a ±2 noise band, so the center #272733 serves both; the original
  /// #2B2B38 read (43,43,56), ~+4 hot and a step too blue).
  static let selectedRow = Color(red: 0x27 / 255, green: 0x27 / 255, blue: 0x33 / 255)
  static let primaryText = Color(red: 0xCF / 255, green: 0xD6 / 255, blue: 0xF1 / 255)
  static let secondaryText = Color(red: 0x8E / 255, green: 0x93 / 255, blue: 0xA9 / 255)
  /// Browse metadata line runs BRIGHTER than the chip/secondary tone:
  /// the live rows' top-decile luminance probes 168 vs our 152 at
  /// `secondaryText` (2026-08-10) -- Raycast uses two secondary tones.
  static let metadataText = Color(red: 0x9E / 255, green: 0xA3 / 255, blue: 0xB9 / 255)
  /// Search placeholder is dimmer than section headers (#64687A probed).
  static let searchPlaceholder = Color(red: 0x64 / 255, green: 0x68 / 255, blue: 0x7A / 255)
  /// The sheet stroke is a bluish-purple hairline, not neutral white:
  /// border pixels probe ~(69,65,90) over the sheet.
  static let border = Color(red: 0x4A / 255, green: 0x46 / 255, blue: 0x60 / 255)
  static let borderWidth: CGFloat = 0.5
  /// Blue "Current" dot in the notes rows (#64A1F1, probed).
  static let currentDot = Color(red: 0x64 / 255, green: 0xA1 / 255, blue: 0xF1 / 255)
  /// Disabled actions dim to ~40% (live disabled icon probes (82,85,101)
  /// against enabled (207,214,241)).
  static let disabledOpacity: CGFloat = 0.4

  /// Sheet outer width: 767px at 2x in David's live captures.
  static let width: CGFloat = 383
  static let cornerRadius: CGFloat = 10
  /// Sheet top sits 100pt below the window top (probed in both modals).
  static let topOffset: CGFloat = 100
  /// Row highlights inset 9.5pt from the sheet edge: both live modals'
  /// selected rects measure 728px wide inside the 766px sheet at 2x
  /// (19px per side, 2026-08-10 native captures); the earlier 6pt inset
  /// drew them 14px too wide. Row CONTENT keeps its screen position via
  /// compensated label pads (the live icon/title ink did not move).
  static let rowInset: CGFloat = 9.5
  /// Actions rows are 42pt TOUCHING: the live selected rect is 84px tall
  /// at 2x -- one full pitch, no inter-row gap (the old 38pt + 4pt
  /// spacing put the same pitch but a visibly shorter highlight).
  static let rowHeight: CGFloat = 42
  static let rowCornerRadius: CGFloat = 6
}

/// The 0.5pt white-0.08 hairline Raycast draws edge-to-edge under the
/// search field of BOTH modals and inside the actions group gaps: a
/// SINGLE pixel at 2x (row-mean scans of the live captures show one
/// ~+18-luminance row, 2026-08-10). Our earlier 1pt rule rendered two
/// rows and read twice as heavy -- David flagged it.
struct RaycastModalHairline: View {
  var body: some View {
    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
  }
}

/// Shared floating-sheet chrome: rounded dark sheet with border and shadow,
/// positioned near the top of the note like Raycast's modals.
struct RaycastModalSheet<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .frame(width: RaycastModalPalette.width)
      .background(
        // Raycast-parity translucency: `.popover` blur under a 0.45 tint
        // (measured match -- see RaycastModalPalette.sheet). The sheet's
        // drop shadow is the CHILD WINDOW's own (window-server,
        // shape-accurate) -- a SwiftUI .shadow of an NSViewRepresentable
        // background does not render reliably.
        SpotNoteVisualEffectView(material: .popover, blendingMode: .behindWindow)
          .clipShape(
            RoundedRectangle(cornerRadius: RaycastModalPalette.cornerRadius, style: .continuous)
          )
          .overlay(
            RoundedRectangle(cornerRadius: RaycastModalPalette.cornerRadius, style: .continuous)
              .fill(RaycastModalPalette.sheet.opacity(RaycastModalPalette.sheetTintOpacity))
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: RaycastModalPalette.cornerRadius, style: .continuous)
          .strokeBorder(
            RaycastModalPalette.border,
            lineWidth: RaycastModalPalette.borderWidth
          )
      )
  }
}

/// Raycast-style search field row shown at the top of the notes,
/// actions, and themes modals.
struct RaycastModalSearchField: View {
  let placeholder: String
  @Binding var text: String
  var onSubmit: () -> Void
  var onEscape: () -> Void
  var onMove: (Int) -> Void
  @FocusState private var focused: Bool

  var body: some View {
    ZStack(alignment: .leading) {
      // Raycast draws the placeholder to the right of the resting caret
      // rather than under it, in a dimmer tone than section headers.
      if text.isEmpty {
        Text(placeholder)
          .font(RaycastFont.regular(16))
          .foregroundStyle(RaycastModalPalette.searchPlaceholder)
          .padding(.leading, 3)
          .allowsHitTesting(false)
      }
      field
    }
    // Caret rests 20pt from the sheet edge (probed x=473 at 2x).
    .padding(.horizontal, 20)
    // Live search zone is 47pt: caret + placeholder center 47px at 2x
    // from the sheet top in both modals (2026-08-10 captures); our 44pt
    // field floated the text 3-4px high.
    .frame(height: 47)
    .onAppear { focused = true }
  }

  private var field: some View {
    TextField("", text: $text)
      .textFieldStyle(.plain)
      .font(RaycastFont.regular(16))
      .foregroundStyle(RaycastModalPalette.primaryText)
      // Raycast's caret is the row text color, not accent blue.
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
      .onKeyPress(.init("w"), phases: .down) { press in
        guard press.modifiers.contains(.control) else { return .ignored }
        text = SearchTextEditing.deleteWordBackward(text)
        return .handled
      }
  }
}

/// The Raycast Notes "Browse Notes" modal: search field, hairline, "Notes"
/// section header, and rows of title + metadata with the current note
/// marked. The live browse modal DOES draw the search hairline (row-mean
/// scan, 2026-08-10: single bright row 94px from the sheet top, same
/// white-0.08 as the actions rule) -- the round-4 "no divider lines
/// anywhere" read came from a coarse threshold scan; do not re-delete it.
struct RaycastNotesModal: View {
  @ObservedObject var controller: FuzzyController
  let currentChatID: UUID?
  let isDeletable: (Chat) -> Bool
  let onPick: (Chat) -> Void
  let onTogglePin: (Chat) -> Void
  let onDelete: (Chat) -> Void
  /// Raycast reveals pin + trash on the row under the POINTER, not the
  /// keyboard selection (David's 2026-08-10 hover captures).
  @State private var hoveredIndex: Int?

  var body: some View {
    RaycastModalSheet {
      VStack(alignment: .leading, spacing: 0) {
        RaycastModalSearchField(
          placeholder: "Search for notes...",
          text: Binding(
            get: { controller.query },
            set: { controller.setQuery($0) }
          ),
          onSubmit: { commit() },
          onEscape: { controller.close() },
          onMove: { controller.moveSelection(by: $0) }
        )
        RaycastModalHairline()
        list
      }
    }
  }

  private var list: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          // Live header zone: hairline to first row box is 77px at 2x
          // with the "Notes" cap-top 37px below the hairline (sits low,
          // not centered) -- 15pt top pad inside a fixed 38.5pt frame.
          Text("Notes")
            .font(RaycastFont.medium(14))
            .foregroundStyle(RaycastModalPalette.secondaryText)
            .padding(.horizontal, 8.5)
            .padding(.top, 15)
            .frame(height: Self.headerHeight, alignment: .topLeading)
          if controller.results.isEmpty {
            Text(controller.query.isEmpty ? "No notes" : "No matches")
              .font(.system(size: 13))
              .foregroundStyle(RaycastModalPalette.secondaryText)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 20)
          } else {
            ForEach(Array(controller.results.enumerated()), id: \.element.id) { index, result in
              row(result, index: index)
                .id(result.id)
            }
          }
        }
        .padding(.horizontal, RaycastModalPalette.rowInset)
      }
      .frame(height: listHeight)
      .onChange(of: controller.selectedIndex) { _, newIndex in
        if let result = controller.results[safe: newIndex] {
          proxy.scrollTo(result.id, anchor: .center)
        }
      }
    }
  }

  /// The list hugs its content like the live app, scrolling only past
  /// six rows: David's 2026-08-10 native capture shows Raycast's browse
  /// displaying six full 70pt rows (1000px modal at 2x) while our 320pt
  /// cap cut row five. The full 6-row panel CLIPS the last row's box by
  /// ~6px at 2x (their sheet is 1005.5px where six untrimmed pitches +
  /// header land at 1011) -- the -3pt tail reproduces it; shorter lists
  /// keep the same 7pt bottom breathing room as the actions menu (ours
  /// previously trailed 20px more than the live sheet).
  private var listHeight: CGFloat {
    guard !controller.results.isEmpty else { return Self.headerHeight + 60 }
    let count = controller.results.count
    let tail: CGFloat = count >= 6 ? -3 : 7
    return Self.headerHeight + Self.rowPitch * CGFloat(min(count, 6)) + tail
  }

  /// Hairline to first row box: 77px at 2x on the live sheet.
  static let headerHeight: CGFloat = 38.5

  /// Live browse rows sit on a 140px-at-2x pitch (title-top to
  /// title-top, 2026-08-10 native capture); ours measured 130px.
  static let rowPitch: CGFloat = 70

  private func row(_ result: FuzzyResult, index: Int) -> some View {
    let isSelected = index == controller.selectedIndex
    return Button {
      controller.selectedIndex = index
      commit()
    } label: {
      HStack(spacing: 10) {
        rowText(result)
        Spacer(minLength: 8)
        // Raycast shows pin + trash on the HOVERED row (pin first, trash
        // trailing); a keyboard-selected row stays clean until the
        // pointer visits it. Vault-backed notes can do neither.
        if hoveredIndex == index, isDeletable(result.chat) {
          pinButton(result)
          deleteButton(result)
        }
      }
      // 8.5pt compensates the 9.5pt rowInset: title ink stays 39px from
      // the sheet edge at 2x (live 38.5) while the highlight narrows.
      .padding(.horizontal, 8.5)
      .frame(height: Self.rowPitch)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: RaycastModalPalette.rowCornerRadius, style: .continuous)
          .fill(isSelected ? RaycastModalPalette.selectedRow : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Raycast's highlight follows the pointer (the hovered row lights,
    // 2026-08-10 side-by-side); keyboard and pointer write the same
    // selection. `hoveredIndex` additionally gates the pin/trash pair.
    .onHover { inside in
      if inside {
        hoveredIndex = index
        controller.selectedIndex = index
      } else if hoveredIndex == index {
        hoveredIndex = nil
      }
    }
  }

  private func rowText(_ result: FuzzyResult) -> some View {
    // Title-to-metadata gap: the live rows carry 27px at 2x between the
    // title's bottom and the metadata's top (2026-08-10 native capture);
    // our spacing-2 rendered 14px and squeezed the whole row.
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 6) {
        if result.chat.isPinned {
          Image(systemName: "pin.fill")
            .font(.system(size: 10))
            .foregroundStyle(RaycastModalPalette.secondaryText)
        }
        Text(result.snippet.isEmpty ? "(empty note)" : result.snippet)
          // Live row titles measure 25px ascender-height at 2x -- our 17
          // rendered 27 (2026-08-10 side-by-side); 16 matches.
          .font(RaycastFont.medium(16))
          .foregroundStyle(RaycastModalPalette.primaryText)
          .lineLimit(1)
      }
      metadataLine(result, isCurrent: result.chat.id == currentChatID)
    }
  }

  /// Hover buttons are Raycast's OWN glyphs (their pin is the Tack, their
  /// trash the round-lid can), not SF Symbols, at the live ~17pt visible
  /// (34px at 2x, 2026-08-10 probe; ratio-0.875 rasters -> frame 19.5).
  private func pinButton(_ result: FuzzyResult) -> some View {
    Button {
      onTogglePin(result.chat)
    } label: {
      hoverIcon("RaycastTack")
    }
    .buttonStyle(.plain)
    .help(result.chat.isPinned ? "Unpin note" : "Pin note")
  }

  private func deleteButton(_ result: FuzzyResult) -> some View {
    Button {
      onDelete(result.chat)
    } label: {
      hoverIcon("RaycastTrash")
    }
    .buttonStyle(.plain)
    .help("Delete note")
  }

  private func hoverIcon(_ resource: String) -> some View {
    Image(nsImage: raycastIconImage(resource))
      .renderingMode(.template)
      .resizable()
      .frame(width: 19.5, height: 19.5)
      // Live pin/trash render at TITLE brightness (peak 221 = the row
      // title's own top-decile, 2026-08-10 native capture) -- tinting
      // them secondaryText read as washed-out copies of Raycast's.
      .foregroundStyle(RaycastModalPalette.primaryText)
      .contentShape(Rectangle())
  }

  /// Raycast marks the open note with a small blue dot before "Current".
  private func metadataLine(_ result: FuzzyResult, isCurrent: Bool) -> some View {
    HStack(spacing: 6) {
      if isCurrent {
        Circle()
          .fill(RaycastModalPalette.currentDot)
          .frame(width: 7, height: 7)
      }
      Text(metadata(result, isCurrent: isCurrent))
        .font(RaycastFont.regular(15))
        .foregroundStyle(RaycastModalPalette.metadataText)
        .lineLimit(1)
    }
  }

  private func metadata(_ result: FuzzyResult, isCurrent: Bool) -> String {
    let characters = "\(result.chat.text.count) characters"
    if isCurrent { return "Current • \(characters)" }
    let opened = Self.relativeOpened(result.chat.updatedAt)
    return "Opened \(opened) • \(characters)"
  }

  static func relativeOpened(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func commit() {
    if let chat = controller.selectedChat() {
      onPick(chat)
      controller.close()
    }
  }
}

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
