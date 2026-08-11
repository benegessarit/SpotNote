import SwiftUI

/// Row glyph in the actions modal and submenus: an exact @raycast/icons
/// raster (frame tuned per asset so visible glyphs match the probed
/// sizes), the custom fanned-cards note-switcher, or a theme swatch dot.
enum RaycastActionIcon {
  case raster(resource: String, frame: CGFloat)
  case stackedCards
  case swatch(Color)
}

/// One SpotNote command -- a row in the Raycast-style actions modal, or,
/// with a `submenu`, a parent row that flies out a nested menu (the port
/// of Raycast AI's "Change Model…" flyout). The shape mirrors Raycast's
/// own shipped submenuModel (sections of {id, title, icon, accessory})
/// so new commands slot in as data, not view code.
struct SpotNoteCommand: Identifiable {
  let id: String
  let title: String
  let icon: RaycastActionIcon
  /// Display keycaps, e.g. ["⌘", "N"]. Empty = no shortcut shown.
  var keys: [String] = []
  /// Spacing group; a gap with a centered separator renders between
  /// groups in the actions modal.
  var section: Int = 0
  /// Inapplicable commands stay listed but dim and can't be selected,
  /// like the live menu's greyed rows.
  var isEnabled: Bool = true
  /// Right-aligned secondary accessory text (e.g. "Current").
  var trailing: String?
  /// Small yellow pill badge before the accessory (e.g. "Beta").
  var chip: String?
  /// Non-nil = →/Enter opens this flyout instead of performing. Built
  /// lazily so dynamic lists (themes) reflect live state at open time.
  var submenu: (() -> SpotNoteSubmenu)?
  var perform: () -> Void = {}
}

/// A flyout submenu: the invoking command's title becomes the dimmed
/// header row, items group into titled sections, and the search field
/// sits at the BOTTOM (Raycast AI's upwardsLayout).
struct SpotNoteSubmenu {
  let title: String
  let sections: [SpotNoteSubmenuSection]
  var searchPlaceholder: String = "Search..."
  var defaultSelectedID: String?
  /// The ⓘ button beside the search field (Raycast AI shows model
  /// info there). Off unless a consumer has something to show.
  var showsInfoButton = false

  /// Sections narrowed to items matching the query; emptied sections
  /// drop entirely (their headers go with them).
  func filtered(query: String) -> [SpotNoteSubmenuSection] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return sections }
    return sections.compactMap { section in
      let items = section.items.filter { $0.title.lowercased().contains(needle) }
      return items.isEmpty
        ? nil : SpotNoteSubmenuSection(title: section.title, items: items)
    }
  }
}

struct SpotNoteSubmenuSection {
  /// Dimmed group caption ("Anthropic" in the capture); nil = an
  /// untitled group like the capture's leading Auto row.
  let title: String?
  let items: [SpotNoteCommand]
}

/// Theme swatch dot: the theme's surface color in a hairline ring,
/// centered in the row's icon frame (the retired themes modal's preview
/// dot, stepped up for the 22pt submenu icon cell).
struct RaycastSwatchDot: View {
  let color: Color

  var body: some View {
    Circle()
      .fill(color)
      .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
      .frame(width: 16, height: 16)
  }
}

/// Selection stepping over the flattened, filtered item list: arrows
/// wrap and skip disabled rows, exactly like the actions modal.
enum SubmenuSelection {
  static func move(from id: String?, by delta: Int, in items: [SpotNoteCommand]) -> String? {
    guard !items.isEmpty else { return nil }
    let start = items.firstIndex(where: { $0.id == id }) ?? 0
    var index = start
    for _ in 0..<items.count {
      index = (index + delta + items.count) % items.count
      if items[index].isEnabled { return items[index].id }
    }
    return nil
  }

  static func firstEnabled(in items: [SpotNoteCommand]) -> String? {
    items.first(where: \.isEnabled)?.id
  }
}

/// Factories for the registry's dynamic submenus.
enum SpotNoteCommands {
  /// Change Theme flyout: themes grouped Dark/Light, the active theme
  /// marked "Current" and selected on open.
  @MainActor
  static func themeSubmenu(preferences: ThemePreferences) -> SpotNoteSubmenu {
    func rows(_ themes: [Theme]) -> [SpotNoteCommand] {
      themes.map { theme in
        SpotNoteCommand(
          id: "theme-\(theme.id)",
          title: theme.name,
          icon: .swatch(theme.background),
          trailing: preferences.selectedThemeID == theme.id ? "Current" : nil,
          perform: { preferences.selectedThemeID = theme.id }
        )
      }
    }
    return SpotNoteSubmenu(
      title: "Change Theme…",
      sections: [
        SpotNoteSubmenuSection(title: "Dark", items: rows(ThemeCatalog.darkThemes)),
        SpotNoteSubmenuSection(title: "Light", items: rows(ThemeCatalog.lightThemes))
      ],
      searchPlaceholder: "Search themes...",
      defaultSelectedID: "theme-\(preferences.selectedThemeID)"
    )
  }
}
