import Foundation
import SwiftUI
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

  @Test("default selected theme is Mirage")
  func defaultsToMirage() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    #expect(prefs.selectedThemeID == ThemeCatalog.mirage.id)
    #expect(prefs.activeTheme.id == ThemeCatalog.mirage.id)
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

  @Test("unknown id falls back to Mirage")
  func unknownFallsBack() {
    #expect(ThemeCatalog.theme(withID: "nope").id == ThemeCatalog.mirage.id)
  }

  @Test("custom Catppuccin, Rose Pine, Ayu, Mirage, Dracula, and nvim-family themes are present")
  func customThemesPresent() {
    let ids = Set(ThemeCatalog.all.map(\.id))
    #expect(ids.contains("catppuccin-frappe"))
    #expect(ids.contains("catppuccin-mocha"))
    #expect(ids.contains("catppuccin-latte"))
    #expect(ids.contains("rose-pine-moonlight"))
    #expect(ids.contains("ayu-mirage"))
    #expect(ids.contains("mirage"))
    #expect(ids.contains("dracula"))
    #expect(ids.contains("nvim-dark"))
    #expect(ids.contains("neobones-dark"))
    #expect(ids.contains("nightfox"))
  }

  @Test("Mirage uses the sourced cmuxthemes terminal palette")
  func miragePalette() {
    let theme = ThemeCatalog.mirage
    #expect(theme.id == "mirage")
    #expect(theme.name == "Mirage")
    #expect(theme.mode == .dark)
    #expect(theme.background == Color(red: 27 / 255, green: 39 / 255, blue: 56 / 255))
    #expect(theme.text == Color(red: 166 / 255, green: 178 / 255, blue: 192 / 255))
    #expect(theme.placeholder == Color(red: 87 / 255, green: 86 / 255, blue: 86 / 255))
  }

  @Test("Ayu Mirage uses the sourced cmuxthemes terminal palette")
  func ayuMiragePalette() {
    let theme = ThemeCatalog.ayuMirage
    #expect(theme.id == "ayu-mirage")
    #expect(theme.name == "Ayu Mirage")
    #expect(theme.mode == .dark)
    #expect(theme.background == Color(red: 31 / 255, green: 36 / 255, blue: 48 / 255))
    #expect(theme.text == Color(red: 204 / 255, green: 202 / 255, blue: 194 / 255))
    #expect(theme.placeholder == Color(red: 104 / 255, green: 104 / 255, blue: 104 / 255))
  }

  @Test("Dracula uses the sourced cmuxthemes terminal palette")
  func draculaPalette() {
    let theme = ThemeCatalog.dracula
    #expect(theme.id == "dracula")
    #expect(theme.name == "Dracula")
    #expect(theme.mode == .dark)
    #expect(theme.background == Color(red: 40 / 255, green: 42 / 255, blue: 54 / 255))
    #expect(theme.text == Color(red: 248 / 255, green: 248 / 255, blue: 242 / 255))
    #expect(theme.placeholder == Color(red: 98 / 255, green: 114 / 255, blue: 164 / 255))
  }

  @Test("Nvim Dark uses the sourced cmuxthemes terminal palette")
  func nvimDarkPalette() {
    let theme = ThemeCatalog.nvimDark
    #expect(theme.id == "nvim-dark")
    #expect(theme.name == "Nvim Dark")
    #expect(theme.mode == .dark)
    #expect(theme.background == Color(red: 20 / 255, green: 22 / 255, blue: 27 / 255))
    #expect(theme.text == Color(red: 224 / 255, green: 226 / 255, blue: 234 / 255))
    #expect(theme.placeholder == Color(red: 79 / 255, green: 82 / 255, blue: 88 / 255))
  }

  @Test("Neobones Dark uses the sourced cmuxthemes terminal palette")
  func neobonesDarkPalette() {
    let theme = ThemeCatalog.neobonesDark
    #expect(theme.id == "neobones-dark")
    #expect(theme.name == "Neobones Dark")
    #expect(theme.mode == .dark)
    #expect(theme.background == Color(red: 15 / 255, green: 25 / 255, blue: 31 / 255))
    #expect(theme.text == Color(red: 198 / 255, green: 213 / 255, blue: 207 / 255))
    #expect(theme.placeholder == Color(red: 51 / 255, green: 70 / 255, blue: 82 / 255))
  }

  @Test("Nightfox uses the sourced cmuxthemes terminal palette")
  func nightfoxPalette() {
    let theme = ThemeCatalog.nightfox
    #expect(theme.id == "nightfox")
    #expect(theme.name == "Nightfox")
    #expect(theme.mode == .dark)
    #expect(theme.background == Color(red: 25 / 255, green: 35 / 255, blue: 48 / 255))
    #expect(theme.text == Color(red: 205 / 255, green: 206 / 255, blue: 207 / 255))
    #expect(theme.placeholder == Color(red: 87 / 255, green: 88 / 255, blue: 96 / 255))
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
    #expect(ThemeCatalog.darkThemes.count == 14)
    #expect(ThemeCatalog.lightThemes.count == 6)
    #expect(ThemeCatalog.all.count == 20)
  }

  @Test("showLineNumbers defaults to false on first launch")
  func lineNumbersDefaultOn() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    #expect(prefs.showLineNumbers == false)
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

  @Test("maxVisibleLines defaults to the roomy 9-line HUD on first launch")
  func maxVisibleLinesDefault() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    #expect(prefs.maxVisibleLines == ThemePreferences.defaultVisibleLines)
    #expect(prefs.maxVisibleLines == 9)
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
