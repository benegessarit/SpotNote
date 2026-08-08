import SwiftUI

/// Raycast Notes-style title bar: system traffic lights live at the leading
/// edge (drawn by the titled window, not here), the note's first line is
/// centered as the title, and a trailing rounded pill holds the shortcut,
/// note-switcher, and new-note buttons.
struct RaycastTopBar: View {
  let title: String
  let theme: Theme
  let onShowShortcuts: () -> Void
  let onToggleNotes: () -> Void
  let onNewNote: () -> Void
  @Binding var shortcutsShown: Bool

  /// Width reserved at the leading edge for the system traffic lights.
  static let trafficLightGutter: CGFloat = 80

  var body: some View {
    ZStack {
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.placeholder)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Self.trafficLightGutter + 8)
      HStack {
        Spacer()
        iconPill
      }
      .padding(.trailing, 12)
    }
    .frame(height: EditorMetrics.topBarHeight)
  }

  private var iconPill: some View {
    HStack(spacing: 2) {
      pillButton(systemName: "command", help: "Keyboard shortcuts") {
        onShowShortcuts()
      }
      .popover(isPresented: $shortcutsShown, arrowEdge: .bottom) {
        RaycastShortcutsPopover(theme: theme)
      }
      pillButton(systemName: "square.on.square", help: "Switch note") {
        onToggleNotes()
      }
      pillButton(systemName: "plus", help: "New note") {
        onNewNote()
      }
    }
    .padding(.horizontal, 4)
    .frame(height: 32)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.white.opacity(0.06))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    )
  }

  private func pillButton(
    systemName: String,
    help: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.5))
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}

/// Raycast Notes-style bottom bar: centered live character counter and a
/// trailing circled "T" theme picker.
struct RaycastBottomBar: View {
  let characterCount: Int
  let theme: Theme
  @ObservedObject var preferences: ThemePreferences
  @Binding var themePickerShown: Bool

  var body: some View {
    ZStack {
      Text(counterText)
        .font(.system(size: 12))
        .foregroundStyle(theme.placeholder)
      HStack {
        Spacer()
        themeButton
      }
      .padding(.trailing, 14)
    }
    .frame(height: EditorMetrics.bottomBarHeight)
  }

  private var counterText: String {
    characterCount == 1 ? "1 character" : "\(characterCount) characters"
  }

  private var themeButton: some View {
    Button {
      themePickerShown.toggle()
    } label: {
      Text("T")
        .font(.system(size: 13, weight: .medium, design: .serif))
        .foregroundStyle(Color.white.opacity(0.6))
        .frame(width: 28, height: 28)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help("Theme")
    .popover(isPresented: $themePickerShown, arrowEdge: .top) {
      RaycastThemePopover(preferences: preferences)
    }
  }
}

/// Compact theme list shown from the bottom bar's "T" button.
struct RaycastThemePopover: View {
  @ObservedObject var preferences: ThemePreferences

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(ThemeCatalog.all) { theme in
          Button {
            preferences.selectedThemeID = theme.id
          } label: {
            HStack {
              Circle()
                .fill(theme.background)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                .frame(width: 12, height: 12)
              Text(theme.name)
              Spacer()
              if preferences.selectedThemeID == theme.id {
                Image(systemName: "checkmark")
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(.vertical, 3)
          .padding(.horizontal, 6)
        }
      }
      .padding(8)
    }
    .frame(width: 220, height: 280)
  }
}

/// Static shortcut reference shown from the title bar's command button,
/// backed by the same catalog as the Settings vim pane.
struct RaycastShortcutsPopover: View {
  let theme: Theme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(VimCommandReference.sections) { section in
          VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
            ForEach(section.entries) { entry in
              HStack(alignment: .top) {
                Text(entry.usage)
                  .font(.system(size: 11, design: .monospaced))
                  .frame(width: 130, alignment: .leading)
                Text(entry.summary)
                  .font(.system(size: 11))
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .padding(12)
    }
    .frame(width: 380, height: 320)
  }
}
