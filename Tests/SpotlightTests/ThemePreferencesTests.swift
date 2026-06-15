import Foundation
import Testing

@testable import Spotlight

@Suite("ThemePreferences")
@MainActor
struct ThemePreferencesTests {
  private func makeDefaults() -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: "spotnote.tests.\(UUID())") else {
      Issue.record("UserDefaults suite creation failed")
      return .standard
    }
    return defaults
  }

  @Test("default selected theme is Catppuccin Frappe")
  func defaultsToCatppuccinFrappe() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    #expect(prefs.selectedThemeID == ThemeCatalog.catppuccinFrappe.id)
    #expect(prefs.activeTheme.id == ThemeCatalog.catppuccinFrappe.id)
  }

  @Test("setting selectedThemeID persists to UserDefaults")
  func selectionPersists() {
    let defaults = makeDefaults()
    let prefs = ThemePreferences(defaults: defaults)
    prefs.selectedThemeID = ThemeCatalog.midnight.id
    #expect(defaults.string(forKey: "theme.selected.id") == ThemeCatalog.midnight.id)
  }

  @Test("a light theme may be selected while on a dark system and vice versa")
  func crossModeSelectionWorks() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    prefs.selectedThemeID = ThemeCatalog.bone.id
    #expect(prefs.activeTheme.mode == .light)
    prefs.selectedThemeID = ThemeCatalog.charcoal.id
    #expect(prefs.activeTheme.mode == .dark)
  }

  @Test("preferences rehydrate from a previously populated UserDefaults")
  func rehydrates() {
    let defaults = makeDefaults()
    defaults.set(ThemeCatalog.ink.id, forKey: "theme.selected.id")
    let prefs = ThemePreferences(defaults: defaults)
    #expect(prefs.selectedThemeID == ThemeCatalog.ink.id)
  }

  @Test("unknown id falls back to Catppuccin Frappe")
  func unknownFallsBack() {
    #expect(ThemeCatalog.theme(withID: "nope").id == ThemeCatalog.catppuccinFrappe.id)
  }

  @Test("custom Catppuccin and Rose Pine themes are present")
  func customThemesPresent() {
    let ids = Set(ThemeCatalog.all.map(\.id))
    #expect(ids.contains("catppuccin-frappe"))
    #expect(ids.contains("catppuccin-mocha"))
    #expect(ids.contains("catppuccin-latte"))
    #expect(ids.contains("rose-pine-moonlight"))
  }

  @Test("all dark themes have mode .dark; all light themes have mode .light")
  func themeModesAreConsistent() {
    for theme in ThemeCatalog.darkThemes {
      #expect(theme.mode == .dark, "\(theme.name) should be dark")
    }
    for theme in ThemeCatalog.lightThemes {
      #expect(theme.mode == .light, "\(theme.name) should be light")
    }
  }

  @Test("catalog restores neutral and custom themes")
  func catalogSize() {
    #expect(ThemeCatalog.darkThemes.count == 8)
    #expect(ThemeCatalog.lightThemes.count == 6)
    #expect(ThemeCatalog.all.count == 14)
  }

  @Test("showLineNumbers defaults to true on first launch")
  func lineNumbersDefaultOn() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    #expect(prefs.showLineNumbers == true)
  }

  @Test("showLineNumbers persists to UserDefaults, including the off value")
  func lineNumbersPersist() {
    let defaults = makeDefaults()
    let prefs = ThemePreferences(defaults: defaults)
    prefs.showLineNumbers = false
    #expect(defaults.bool(forKey: "editor.showLineNumbers") == false)
    let rehydrated = ThemePreferences(defaults: defaults)
    #expect(rehydrated.showLineNumbers == false)
  }

  @Test("showMenuBarIcon defaults to true on first launch")
  func menuBarIconDefaultsOn() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    #expect(prefs.showMenuBarIcon == true)
  }

  @Test("showMenuBarIcon persists to UserDefaults, including the off value")
  func menuBarIconPersists() {
    let defaults = makeDefaults()
    let prefs = ThemePreferences(defaults: defaults)
    prefs.showMenuBarIcon = false
    #expect(defaults.bool(forKey: "menubar.showIcon") == false)
    let rehydrated = ThemePreferences(defaults: defaults)
    #expect(rehydrated.showMenuBarIcon == false)
  }

  @Test("maxVisibleLines defaults to 3 on first launch")
  func maxVisibleLinesDefault() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    #expect(prefs.maxVisibleLines == ThemePreferences.defaultVisibleLines)
    #expect(prefs.maxVisibleLines == 3)
  }

  @Test("maxVisibleLines persists and rehydrates")
  func maxVisibleLinesPersists() {
    let defaults = makeDefaults()
    let prefs = ThemePreferences(defaults: defaults)
    prefs.maxVisibleLines = 12
    #expect(defaults.integer(forKey: "editor.maxVisibleLines") == 12)
    let rehydrated = ThemePreferences(defaults: defaults)
    #expect(rehydrated.maxVisibleLines == 12)
  }

  @Test("maxVisibleLines clamps out-of-range values in the setter")
  func maxVisibleLinesClamps() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    prefs.maxVisibleLines = 0
    #expect(prefs.maxVisibleLines == ThemePreferences.minVisibleLines)
    prefs.maxVisibleLines = 500
    #expect(prefs.maxVisibleLines == ThemePreferences.maxVisibleLinesCap)
    prefs.maxVisibleLines = -10
    #expect(prefs.maxVisibleLines == ThemePreferences.minVisibleLines)
  }

  @Test("maxVisibleLines clamps a corrupt stored value on rehydrate")
  func maxVisibleLinesClampsOnLoad() {
    let defaults = makeDefaults()
    defaults.set(999, forKey: "editor.maxVisibleLines")
    let prefs = ThemePreferences(defaults: defaults)
    #expect(prefs.maxVisibleLines == ThemePreferences.maxVisibleLinesCap)
  }

  @Test("showHints defaults to true on first launch")
  func tutorialDefaultsOn() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    #expect(prefs.showHints == true)
  }

  @Test("showHints persists to UserDefaults, including the off value")
  func tutorialPersists() {
    let defaults = makeDefaults()
    let prefs = ThemePreferences(defaults: defaults)
    prefs.showHints = false
    #expect(defaults.bool(forKey: "hud.showHints") == false)
    let rehydrated = ThemePreferences(defaults: defaults)
    #expect(rehydrated.showHints == false)
  }
}
