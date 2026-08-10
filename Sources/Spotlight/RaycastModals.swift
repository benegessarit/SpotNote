import Core
import SwiftUI

/// Palette for the Raycast Notes floating modals (Browse Notes, Actions).
/// Pixel-sampled from the live Raycast Beta Notes modals: the sheet is
/// DARKER than the note surface, with a soft hover row and muted metadata.
enum RaycastModalPalette {
  /// The sheet is a translucent MATERIAL, not opaque paint: the live
  /// Raycast sheet transmits ~21% of the blurred backdrop (a blue chat
  /// row behind it lifts B by 43/200 of the raw delta) and DARKENS red
  /// (tR ~ -0.19, a desaturating material). Swatch-lab sweeps of
  /// (material x tint) against uniform blue/dark backdrops (2026-08-09)
  /// matched that signature with `.popover` under this ink at 0.45:
  /// composite over a (31,31,46) backdrop measures (34,35,46) vs
  /// Raycast's (33,34,45), transmission (-0.22, 0.23, 0.21) vs their
  /// (-0.19, ~0.14, 0.215). A 0.90 tint (the first attempt) matched the
  /// composite but killed the bleed entirely (t ~ 0.02).
  static let sheet = Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x28 / 255)
  static let sheetTintOpacity: CGFloat = 0.45
  /// Selected row (43,43,56) probed on the live actions menu.
  static let selectedRow = Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x38 / 255)
  static let primaryText = Color(red: 0xCF / 255, green: 0xD6 / 255, blue: 0xF1 / 255)
  static let secondaryText = Color(red: 0x8E / 255, green: 0x93 / 255, blue: 0xA9 / 255)
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
  /// Row rects inset 6pt from the sheet edge; 38pt tall on 42pt pitch.
  static let rowInset: CGFloat = 6
  static let rowHeight: CGFloat = 38
  static let rowSpacing: CGFloat = 4
  static let rowCornerRadius: CGFloat = 6
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
          .font(.system(size: 16))
          .foregroundStyle(RaycastModalPalette.searchPlaceholder)
          .padding(.leading, 3)
          .allowsHitTesting(false)
      }
      field
    }
    // Caret rests 20pt from the sheet edge (probed x=473 at 2x).
    .padding(.horizontal, 20)
    .frame(height: 44)
    .onAppear { focused = true }
  }

  private var field: some View {
    TextField("", text: $text)
      .textFieldStyle(.plain)
      .font(.system(size: 16))
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

/// The Raycast Notes "Browse Notes" modal: search field, "Notes" section
/// header, and rows of title + metadata with the current note marked.
/// Raycast separates the regions with spacing only -- no divider lines
/// anywhere in the sheet (pixel-probed).
struct RaycastNotesModal: View {
  @ObservedObject var controller: FuzzyController
  let currentChatID: UUID?
  let isDeletable: (Chat) -> Bool
  let onPick: (Chat) -> Void
  let onTogglePin: (Chat) -> Void
  let onDelete: (Chat) -> Void

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
        list
      }
      .padding(.bottom, 8)
    }
  }

  private var list: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          Text("Notes")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(RaycastModalPalette.secondaryText)
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 8)
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
      .frame(maxHeight: 320)
      .onChange(of: controller.selectedIndex) { _, newIndex in
        if let result = controller.results[safe: newIndex] {
          proxy.scrollTo(result.id, anchor: .center)
        }
      }
    }
  }

  private func row(_ result: FuzzyResult, index: Int) -> some View {
    let isSelected = index == controller.selectedIndex
    return Button {
      controller.selectedIndex = index
      commit()
    } label: {
      HStack(spacing: 10) {
        rowText(result)
        Spacer(minLength: 8)
        // Raycast shows pin + trash on the SELECTED row only (pin first,
        // trash trailing). Vault-backed notes can do neither.
        if isSelected, isDeletable(result.chat) {
          pinButton(result)
          deleteButton(result)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: RaycastModalPalette.rowCornerRadius, style: .continuous)
          .fill(isSelected ? RaycastModalPalette.selectedRow : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func rowText(_ result: FuzzyResult) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        if result.chat.isPinned {
          Image(systemName: "pin.fill")
            .font(.system(size: 10))
            .foregroundStyle(RaycastModalPalette.secondaryText)
        }
        Text(result.snippet.isEmpty ? "(empty note)" : result.snippet)
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(RaycastModalPalette.primaryText)
          .lineLimit(1)
      }
      metadataLine(result, isCurrent: result.chat.id == currentChatID)
    }
  }

  private func pinButton(_ result: FuzzyResult) -> some View {
    Button {
      onTogglePin(result.chat)
    } label: {
      Image(systemName: result.chat.isPinned ? "pin.slash" : "pin")
        .font(.system(size: 13))
        .foregroundStyle(RaycastModalPalette.secondaryText)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(result.chat.isPinned ? "Unpin note" : "Pin note")
  }

  private func deleteButton(_ result: FuzzyResult) -> some View {
    Button {
      onDelete(result.chat)
    } label: {
      Image(systemName: "trash")
        .font(.system(size: 13))
        .foregroundStyle(RaycastModalPalette.secondaryText)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Delete note")
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
        .font(.system(size: 15))
        .foregroundStyle(RaycastModalPalette.secondaryText)
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
