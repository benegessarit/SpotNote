import Core
import SwiftUI

/// Palette for the Raycast Notes floating modals (Browse Notes, Actions).
/// Pixel-sampled from the live Raycast Beta Notes modals: the sheet is
/// DARKER than the note surface, with a soft hover row and muted metadata.
enum RaycastModalPalette {
  static let sheet = Color(red: 0x1D / 255, green: 0x1E / 255, blue: 0x29 / 255)
  static let selectedRow = Color(red: 0x26 / 255, green: 0x28 / 255, blue: 0x33 / 255)
  static let primaryText = Color(red: 0xCF / 255, green: 0xD6 / 255, blue: 0xF1 / 255)
  static let secondaryText = Color(red: 0x8E / 255, green: 0x93 / 255, blue: 0xA9 / 255)
  static let border = Color.white.opacity(0.08)
  static let backdrop = Color.black.opacity(0.35)

  static let width: CGFloat = 480
  static let cornerRadius: CGFloat = 12
  static let topOffset: CGFloat = 88
}

/// Shared floating-sheet chrome: rounded dark sheet with border and shadow,
/// positioned near the top of the note like Raycast's modals.
private struct RaycastModalSheet<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .frame(width: RaycastModalPalette.width)
      .background(
        RoundedRectangle(cornerRadius: RaycastModalPalette.cornerRadius, style: .continuous)
          .fill(RaycastModalPalette.sheet)
      )
      .overlay(
        RoundedRectangle(cornerRadius: RaycastModalPalette.cornerRadius, style: .continuous)
          .strokeBorder(RaycastModalPalette.border, lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
  }
}

/// Raycast-style search field row shown at the top of both modals.
private struct RaycastModalSearchField: View {
  let placeholder: String
  @Binding var text: String
  var onSubmit: () -> Void
  var onEscape: () -> Void
  var onMove: (Int) -> Void
  @FocusState private var focused: Bool

  var body: some View {
    TextField(placeholder, text: $text)
      .textFieldStyle(.plain)
      .font(.system(size: 15))
      .foregroundStyle(RaycastModalPalette.primaryText)
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
      .padding(.horizontal, 16)
      .frame(height: 48)
      .onAppear { focused = true }
  }
}

private var modalDivider: some View {
  Rectangle()
    .fill(Color.white.opacity(0.06))
    .frame(height: 1)
}

/// The Raycast Notes "Browse Notes" modal: search field, "Notes" section
/// header, and rows of title + metadata with the current note marked.
struct RaycastNotesModal: View {
  @ObservedObject var controller: FuzzyController
  let currentChatID: UUID?
  let onPick: (Chat) -> Void

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
        modalDivider
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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(RaycastModalPalette.secondaryText)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
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
        .padding(.horizontal, 8)
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
    let isCurrent = result.chat.id == currentChatID
    let title = result.snippet.isEmpty ? "(empty note)" : result.snippet
    return Button {
      controller.selectedIndex = index
      commit()
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          if result.chat.isPinned {
            Image(systemName: "pin.fill")
              .font(.system(size: 10))
              .foregroundStyle(RaycastModalPalette.secondaryText)
          }
          Text(title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(RaycastModalPalette.primaryText)
            .lineLimit(1)
        }
        Text(metadata(result, isCurrent: isCurrent))
          .font(.system(size: 12))
          .foregroundStyle(RaycastModalPalette.secondaryText)
          .lineLimit(1)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? RaycastModalPalette.selectedRow : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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

/// One entry in the Raycast-style actions modal.
struct RaycastAction: Identifiable {
  let id: String
  let title: String
  let systemImage: String
  /// Display keycaps, e.g. ["⌘", "N"]. Empty = no shortcut shown.
  let keys: [String]
  /// Divider group; a thin rule renders between groups.
  let section: Int
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
        modalDivider
        list
      }
      .padding(.bottom, 8)
    }
    .onChange(of: query) { _, _ in selectedIndex = 0 }
  }

  private var list: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
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
              modalDivider
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            row(action, index: index)
          }
        }
      }
      .padding(.horizontal, 8)
      .padding(.top, 8)
    }
    .frame(maxHeight: 340)
  }

  private func row(_ action: RaycastAction, index: Int) -> some View {
    let isSelected = index == selectedIndex
    return Button {
      selectedIndex = index
      commit()
    } label: {
      HStack(spacing: 10) {
        Image(systemName: action.systemImage)
          .font(.system(size: 13))
          .foregroundStyle(RaycastModalPalette.secondaryText)
          .frame(width: 18)
        Text(action.title)
          .font(.system(size: 14))
          .foregroundStyle(RaycastModalPalette.primaryText)
        Spacer(minLength: 12)
        keycaps(action.keys)
      }
      .padding(.horizontal, 8)
      .frame(height: 40)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? RaycastModalPalette.selectedRow : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func keycaps(_ keys: [String]) -> some View {
    if !keys.isEmpty {
      HStack(spacing: 4) {
        ForEach(keys, id: \.self) { key in
          Text(key)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(RaycastModalPalette.secondaryText)
            .frame(minWidth: 22)
            .frame(height: 22)
            .background(
              RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.07))
            )
        }
      }
    }
  }

  private func move(_ delta: Int) {
    let count = filtered.count
    guard count > 0 else { return }
    selectedIndex = (selectedIndex + delta + count) % count
  }

  private func commit() {
    let rows = filtered
    guard rows.indices.contains(selectedIndex) else { return }
    let action = rows[selectedIndex]
    onClose()
    action.perform()
  }
}
