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
  /// PRE-macOS-26 fallback ink only. The live sheet is the SYSTEM GLASS
  /// material (see SpotNoteGlassBackdrop): round-12 same-frame captures
  /// measure it transmitting ~48% of the backdrop per channel (B 27/56,
  /// G 16/33) -- the 2026-08-09 swatch-lab ~21% read predates Raycast's
  /// glass adoption and is stale. `.popover` + this 0.45 tint only
  /// reaches t ~ 0.2; no tint over `.popover` can reach 0.48, so the
  /// glass path carries parity and this pair only serves older systems.
  static let sheet = Color(red: 0x10 / 255, green: 0x12 / 255, blue: 0x19 / 255)
  static let sheetTintOpacity: CGFloat = 0.45
  /// Selected/hovered row: their stylesheet fills it TRANSLUCENT --
  /// `--list-item-hover-background-color: var(--selection-5)`, and with
  /// the theme's selection at the primary fg, 5% of #CFD6F1 over the
  /// probed sheet reproduces the live composites exactly ((40,40,52)
  /// actions, (38,38,50) browse: delta (9,7,10) = 0.05 x (fg - sheet)).
  /// The old opaque #272733 matched those probes too but blocks the
  /// glass bleed inside the highlight.
  static let selectedRow = primaryText.opacity(0.05)
  static let primaryText = Color(red: 0xCF / 255, green: 0xD6 / 255, blue: 0xF1 / 255)
  static let secondaryText = Color(red: 0x8E / 255, green: 0x93 / 255, blue: 0xA9 / 255)
  /// Browse metadata line runs BRIGHTER than the chip/secondary tone:
  /// the live rows' top-decile luminance probes 168 vs our 152 at
  /// `secondaryText` (2026-08-10) -- Raycast uses two secondary tones.
  static let metadataText = Color(red: 0x9E / 255, green: 0xA3 / 255, blue: 0xB9 / 255)
  /// Search placeholder is dimmer than section headers (#64687A probed).
  static let searchPlaceholder = Color(red: 0x64 / 255, green: 0x68 / 255, blue: 0x7A / 255)
  /// Raycast's whole modal ink system is ONE foreground (#CFD6F1 =
  /// `primaryText`) at opacity tiers -- their shipped stylesheet
  /// (`notes-window-*.css` + tokens in the app bundle's frontend dir)
  /// defines --color-text-secondary: fg/60%, --color-border-token:
  /// fg/20%, --color-border-separator: fg/10%, and the pixel probes
  /// confirm each composite exactly (chip outline (64,66,80) = fg-20
  /// over the sheet; chip glyph (136,140,161) = fg-60; hairline
  /// (49,50,62) = fg-10). Derive, don't hand-pick grays.
  static let borderInk = primaryText.opacity(0.2)
  static let hairlineInk = primaryText.opacity(0.10)
  static let secondaryInk = primaryText.opacity(0.6)
  /// The menu border is the SAME fg-20 token as the keycap outline
  /// (`--shadow-panel-border: inset 0 0 0 1px var(--fg-20)`). The live
  /// edge profile at 2x is ONE strong pixel (~+42 over backdrop) plus
  /// one falloff pixel (~+22) -- about 1.5 device px of ink; our 1pt
  /// stroke drew two full-strength pixels (~+75 each) and read heavy
  /// (round 12). 0.75pt antialiases to their exact profile.
  static let border = borderInk
  static let borderWidth: CGFloat = 0.75
  /// Blue "Current" dot in the notes rows (#64A1F1, probed).
  static let currentDot = Color(red: 0x64 / 255, green: 0xA1 / 255, blue: 0xF1 / 255)
  /// Disabled actions dim to 30% -- their stylesheet's
  /// `[data-disabled]{opacity:.3}`. The composite confirms it: 0.3 x fg
  /// + 0.7 x sheet = (82,87,105) against the live probe (82,85,101);
  /// the earlier 0.4 divided ink by fg alone and ignored the sheet
  /// showing through the translucent glyph.
  static let disabledOpacity: CGFloat = 0.3

  /// Sheet outer width: 767px at 2x in David's live captures.
  static let width: CGFloat = 383
  /// Circle-fit on the live menu's corner arc (x-of-border vs y from the
  /// sheet top, 2026-08-10 full-res capture) gives r = 33px at 2x; the
  /// stylesheet's radius-12 at the notes window's render scale agrees.
  /// The old 10pt read visibly squarer than the live menu.
  static let cornerRadius: CGFloat = 16.5
  /// Sheet top sits 100pt below the window top (probed in both modals).
  static let topOffset: CGFloat = 100
  /// Row highlights inset 9.5pt from the sheet edge: both live modals'
  /// selected rects measure 728px wide inside the 766px sheet at 2x
  /// (19px per side, 2026-08-10 native captures); the earlier 6pt inset
  /// drew them 14px too wide. Row CONTENT keeps its screen position via
  /// compensated label pads (the live icon/title ink did not move).
  static let rowInset: CGFloat = 9.5
  /// Actions rows are 43pt TOUCHING: the live menu's icon centers sit on
  /// an 86.0px pitch at 2x (five consecutive deltas, round-12 same-frame
  /// capture) -- the round-10 "84px" was the highlight rect read a hair
  /// short, and the 1pt-per-row deficit is part of what read as "their
  /// menu is bigger".
  static let rowHeight: CGFloat = 43
  static let rowCornerRadius: CGFloat = 6
}

/// The 0.5pt hairline Raycast draws edge-to-edge under the search field
/// of BOTH modals and inside the actions group gaps: a SINGLE pixel at
/// 2x (row-mean scans of the live captures show one ~+18-luminance row,
/// 2026-08-10). Our earlier 1pt rule rendered two rows and read twice as
/// heavy -- David flagged it. Ink is fg-10 (their
/// --color-border-separator), which the live probe (49,50,62) matches
/// exactly; plain white-0.08 sat a step too neutral.
struct RaycastModalHairline: View {
  var body: some View {
    Rectangle().fill(RaycastModalPalette.hairlineInk).frame(height: 0.5)
  }
}

/// Shared floating-sheet chrome: rounded dark sheet with border and shadow,
/// positioned near the top of the note like Raycast's modals.
struct RaycastModalSheet<Content: View>: View {
  let content: Content
  let width: CGFloat

  init(width: CGFloat = RaycastModalPalette.width, @ViewBuilder content: () -> Content) {
    self.width = width
    self.content = content()
  }

  var body: some View {
    content
      .frame(width: width)
      .background(backdrop)
      .overlay(
        RoundedRectangle(cornerRadius: RaycastModalPalette.cornerRadius, style: .continuous)
          .strokeBorder(
            RaycastModalPalette.border,
            lineWidth: RaycastModalPalette.borderWidth
          )
      )
  }

  /// The live sheet is the system glass material -- bare, no tint: their
  /// macOS stylesheet puts `-apple-system-glass-material` on the popover
  /// and paints no ink over it (the gradient stack in the sibling rule
  /// is the non-macOS fallback), which is how it transmits the measured
  /// ~48% of backdrop. Any overlay here would cut that transmission --
  /// resist re-adding one; fix color deltas in the glass config or ink
  /// tiers instead. Pre-26 systems keep the popover+tint approximation.
  @ViewBuilder private var backdrop: some View {
    if #available(macOS 26.0, *) {
      SpotNoteGlassBackdrop(cornerRadius: RaycastModalPalette.cornerRadius)
    } else {
      SpotNoteVisualEffectView(material: .popover, blendingMode: .behindWindow)
        .clipShape(
          RoundedRectangle(cornerRadius: RaycastModalPalette.cornerRadius, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: RaycastModalPalette.cornerRadius, style: .continuous)
            .fill(RaycastModalPalette.sheet.opacity(RaycastModalPalette.sheetTintOpacity))
        )
    }
  }
}

/// Raycast-style search field row shown at the top of the notes
/// and actions modals.
struct RaycastModalSearchField: View {
  let placeholder: String
  @Binding var text: String
  var onSubmit: () -> Void
  var onEscape: () -> Void
  var onMove: (Int) -> Void
  /// → hook for submenu-opening rows; return false to keep the arrow a
  /// normal caret move (the default for modals without submenus).
  var onRight: () -> Bool = { false }
  @FocusState private var focused: Bool

  var body: some View {
    ZStack(alignment: .leading) {
      // The live placeholder ink starts AT the caret rest (x-off 40px at
      // 2x = the 20pt field pad exactly, round-12 capture) -- the old
      // 3pt lead pushed ours ~6px right of theirs.
      if text.isEmpty {
        Text(placeholder)
          .font(RaycastFont.regular(16))
          .foregroundStyle(RaycastModalPalette.searchPlaceholder)
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
      .onKeyPress(.rightArrow) {
        onRight() ? .handled : .ignored
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
  /// Keyboard moves animate the list to the new selection; hover-driven
  /// selection must NOT re-scroll (rows sliding under the pointer during
  /// a trackpad scroll would retarget selection and fight the scroll --
  /// the "rubber-banding" jank Raycast doesn't have).
  @State private var pendingKeyboardScroll = false

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
          onMove: { delta in
            pendingKeyboardScroll = true
            controller.moveSelection(by: delta)
          }
        )
        RaycastModalHairline()
        list
      }
    }
  }

  private var list: some View {
    ScrollViewReader { proxy in
      ScrollView {
        // Eager VStack, not LazyVStack: rows are cheap fixed-height text
        // and lazy instantiation hitches mid-flick; building them all up
        // front is what keeps the trackpad scroll continuous.
        VStack(alignment: .leading, spacing: 0) {
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
        // Only keyboard moves steer the scroll, and they glide like
        // Raycast's list instead of teleporting.
        guard pendingKeyboardScroll else { return }
        pendingKeyboardScroll = false
        if let result = controller.results[safe: newIndex] {
          withAnimation(.easeOut(duration: 0.16)) {
            proxy.scrollTo(result.id, anchor: .center)
          }
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
        // Raycast shows pin + trash on the SELECTED row (their browse
        // rows render accessories under `e.isSelected` -- shipped
        // notes-window JS), so keyboard highlight reveals them too; the
        // pointer path still works because hover writes the same
        // selection. Round-12 same-frame capture: their glyph-ink gap is
        // 48px at 2x (ours at 17pt spacing drew 42) and the trash ink
        // rests 51px from the sheet edge (ours 39) -- hence spacing 20
        // and the extra 6pt trailing. Vault-backed notes show neither.
        if controller.selectedIndex == index, isDeletable(result.chat) {
          HStack(spacing: 20) {
            pinButton(result)
            deleteButton(result)
          }
          .padding(.trailing, 6)
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
    // selection, which also reveals the pin/trash pair.
    .onHover { inside in
      if inside {
        controller.selectedIndex = index
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
