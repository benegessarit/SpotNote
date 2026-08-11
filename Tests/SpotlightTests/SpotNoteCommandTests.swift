import SwiftUI
import Testing

@testable import Spotlight

/// The command registry + submenu model: filtering, selection stepping,
/// and the Change Theme flyout factory (B1/B3 of the submenu program).
@MainActor
struct SpotNoteCommandTests {
  private func submenu() -> SpotNoteSubmenu {
    SpotNoteSubmenu(
      title: "Change Fruit…",
      sections: [
        SpotNoteSubmenuSection(
          title: nil,
          items: [SpotNoteCommand(id: "auto", title: "Auto", icon: .stackedCards)]
        ),
        SpotNoteSubmenuSection(
          title: "Citrus",
          items: [
            SpotNoteCommand(id: "lemon", title: "Lemon", icon: .stackedCards),
            SpotNoteCommand(
              id: "lime",
              title: "Lime",
              icon: .stackedCards,
              isEnabled: false
            )
          ]
        ),
        SpotNoteSubmenuSection(
          title: "Stone",
          items: [SpotNoteCommand(id: "peach", title: "Peach", icon: .stackedCards)]
        )
      ],
      defaultSelectedID: "lemon"
    )
  }

  @Test("filtering narrows items and drops emptied sections with their headers")
  func filtering() {
    let model = submenu()
    #expect(model.filtered(query: "").count == 3)
    let narrowed = model.filtered(query: "le")
    #expect(narrowed.count == 1)
    #expect(narrowed[0].title == "Citrus")
    #expect(narrowed[0].items.map(\.id) == ["lemon"])
    #expect(model.filtered(query: "zzz").isEmpty)
  }

  @Test("selection steps across sections, wraps, and skips disabled rows")
  func selectionStepping() {
    let items = submenu().sections.flatMap(\.items)
    #expect(SubmenuSelection.move(from: "auto", by: 1, in: items) == "lemon")
    // "lime" is disabled: stepping from lemon lands on peach.
    #expect(SubmenuSelection.move(from: "lemon", by: 1, in: items) == "peach")
    #expect(SubmenuSelection.move(from: "peach", by: 1, in: items) == "auto")
    #expect(SubmenuSelection.move(from: "auto", by: -1, in: items) == "peach")
    #expect(SubmenuSelection.move(from: nil, by: 1, in: []) == nil)
    #expect(SubmenuSelection.firstEnabled(in: items) == "auto")
  }

  @Test("the theme submenu groups Dark/Light, marks Current, and switches on perform")
  func themeSubmenu() throws {
    let defaults = try #require(UserDefaults(suiteName: #function))
    let preferences = ThemePreferences(defaults: defaults)
    preferences.selectedThemeID = ThemeCatalog.darkThemes[0].id
    let model = SpotNoteCommands.themeSubmenu(preferences: preferences)
    #expect(model.sections.map(\.title) == ["Dark", "Light"])
    #expect(model.sections[0].items.count == ThemeCatalog.darkThemes.count)
    #expect(model.sections[1].items.count == ThemeCatalog.lightThemes.count)
    let current = model.sections.flatMap(\.items).filter { $0.trailing == "Current" }
    #expect(current.map(\.id) == ["theme-\(preferences.selectedThemeID)"])
    #expect(model.defaultSelectedID == "theme-\(preferences.selectedThemeID)")
    // Selecting a light theme applies it through the existing path.
    let target = ThemeCatalog.lightThemes[0]
    model.sections[1].items.first(where: { $0.id == "theme-\(target.id)" })?.perform()
    #expect(preferences.selectedThemeID == target.id)
  }

  @Test("the actions registry routes Change Theme through a submenu, not a perform")
  func changeThemeIsSubmenu() throws {
    let defaults = try #require(UserDefaults(suiteName: #function))
    let preferences = ThemePreferences(defaults: defaults)
    let model = SpotNoteCommands.themeSubmenu(preferences: preferences)
    #expect(model.title == "Change Theme…")
    #expect(!model.sections.isEmpty)
  }

  @Test("submenu sheet height hugs content and caps the list")
  func sheetHeight() {
    let model = submenu()
    let natural = RaycastSubmenu.naturalListHeight(for: model.sections)
    // 4 rows + a titled first... the first section is UNtitled (0),
    // then two titled breaks.
    let expected =
      4 * RaycastModalPalette.rowHeight + 2 * RaycastSubmenuMetrics.sectionBreakHeight
    #expect(natural == expected)
    let capped = RaycastSubmenu.sheetHeight(for: model, maxListHeight: 100)
    #expect(
      capped
        == RaycastSubmenuMetrics.headerHeight + 100 + RaycastSubmenuMetrics.searchHeight
    )
  }
}
