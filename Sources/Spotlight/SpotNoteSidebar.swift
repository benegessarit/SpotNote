import Core
import SwiftUI

/// Notes sidebar rendered as a floating SHELF: content for the child
/// panel `SpotlightWindowController.syncSidebarShelf` hangs off the HUD's
/// left edge. It owns its full surface (the HUD's glass recipe, darkened
/// a step) because it is a standalone window, not a pane inside one.
struct SpotNoteSidebar: View {
  @ObservedObject var preferences: ThemePreferences
  @ObservedObject var session: ChatSession
  let onPick: (Chat) -> Void

  @State private var query = ""

  private var theme: Theme { preferences.activeTheme }

  private var shelfShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: EditorMetrics.sidebarShelfCornerRadius, style: .continuous)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      searchField
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
      noteList
    }
    .frame(width: EditorMetrics.sidebarWidth, height: EditorMetrics.sidebarShelfHeight)
    .background {
      SpotNoteVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        .clipShape(shelfShape)
        .overlay(shelfShape.fill(theme.background.opacity(SpotlightRootView.darkGlassTintOpacity)))
        .overlay(shelfShape.fill(sidebarSurface))
    }
    .overlay(shelfShape.strokeBorder(theme.border, lineWidth: 1))
    .colorScheme(theme.mode == .dark ? .dark : .light)
  }

  /// The traffic lights stay in the main window (the shelf no longer
  /// owns its top-left corner); the header is just the title + hide.
  private var header: some View {
    HStack {
      Text("Notes")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.placeholder)
        .padding(.leading, 16)
      Spacer()
      Button {
        preferences.sidebarShown = false
      } label: {
        Image(systemName: "sidebar.left")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(RaycastChromePalette.control)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Hide sidebar")
      .padding(.trailing, 14)
    }
    .frame(height: 44)
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(theme.placeholder)
      TextField("Search", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(theme.text)
    }
    .padding(.horizontal, 8)
    .frame(height: 28)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(theme.text.opacity(0.07))
    )
  }

  private var results: [FuzzyResult] {
    FuzzyController.rank(query: query, in: session.chats, limit: 200)
  }

  private var noteList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 1) {
        ForEach(results) { result in
          row(result)
        }
        if results.isEmpty {
          Text(query.isEmpty ? "No notes" : "No matches")
            .font(.system(size: 12))
            .foregroundStyle(theme.placeholder)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
        }
      }
      .padding(.horizontal, 8)
      .padding(.bottom, 10)
    }
  }

  private func row(_ result: FuzzyResult) -> some View {
    let isCurrent = result.chat.id == session.currentID
    let title = result.snippet.isEmpty ? "(empty note)" : result.snippet
    return Button {
      onPick(result.chat)
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          if result.chat.isPinned {
            Image(systemName: "pin.fill")
              .font(.system(size: 9))
              .foregroundStyle(theme.placeholder)
          }
          Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.text)
            .lineLimit(1)
        }
        Text(RaycastNotesModal.relativeOpened(result.chat.updatedAt))
          .font(.system(size: 11))
          .foregroundStyle(theme.placeholder)
          .lineLimit(1)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(isCurrent ? theme.text.opacity(0.08) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// One darkening step over the theme background, like a native sidebar
  /// pane. On raycast-dark this lands beside the modal sheet shade.
  private var sidebarSurface: Color {
    Color.black.opacity(theme.mode == .dark ? 0.18 : 0.05)
  }
}
