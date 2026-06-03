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

  @Test("default selected theme is Rosé Pine Moonlight")
  func defaultsToRosePineMoonlight() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    #expect(prefs.selectedThemeID == ThemeCatalog.rosePineMoonlight.id)
    #expect(prefs.activeTheme.id == ThemeCatalog.rosePineMoonlight.id)
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

  @Test("unknown id falls back to Rosé Pine Moonlight")
  func unknownFallsBack() {
    #expect(ThemeCatalog.theme(withID: "nope").id == ThemeCatalog.rosePineMoonlight.id)
  }

  @Test("Rosé Pine Moonlight is available as a dark theme")
  func rosePineMoonlightAvailable() {
    let theme = ThemeCatalog.theme(withID: "rose-pine-moonlight")
    #expect(theme.id == ThemeCatalog.rosePineMoonlight.id)
    #expect(theme.name == "Rosé Pine Moonlight")
    #expect(theme.mode == .dark)
    #expect(ThemeCatalog.darkThemes.contains { $0.id == theme.id })
  }

  @Test("Catppuccin Mocha is available as a dark theme")
  func catppuccinMochaAvailable() {
    let theme = ThemeCatalog.theme(withID: "catppuccin-mocha")
    #expect(theme.id == ThemeCatalog.catppuccinMocha.id)
    #expect(theme.name == "Catppuccin Mocha")
    #expect(theme.mode == .dark)
    #expect(ThemeCatalog.darkThemes.contains { $0.id == theme.id })
  }

  @Test("Catppuccin Frappé is available as a dark theme")
  func catppuccinFrappeAvailable() {
    let theme = ThemeCatalog.theme(withID: "catppuccin-frappe")
    #expect(theme.id == ThemeCatalog.catppuccinFrappe.id)
    #expect(theme.name == "Catppuccin Frappé")
    #expect(theme.mode == .dark)
    #expect(ThemeCatalog.darkThemes.contains { $0.id == theme.id })
  }

  @Test("Catppuccin Latte is available as a light theme")
  func catppuccinLatteAvailable() {
    let theme = ThemeCatalog.theme(withID: "catppuccin-latte")
    #expect(theme.id == ThemeCatalog.catppuccinLatte.id)
    #expect(theme.name == "Catppuccin Latte")
    #expect(theme.mode == .light)
    #expect(ThemeCatalog.lightThemes.contains { $0.id == theme.id })
  }

  @Test("Rosé Pine Dawn is available as a light theme")
  func rosePineDawnAvailable() {
    let theme = ThemeCatalog.theme(withID: "rose-pine-dawn")
    #expect(theme.id == ThemeCatalog.rosePineDawn.id)
    #expect(theme.name == "Rosé Pine Dawn")
    #expect(theme.mode == .light)
    #expect(ThemeCatalog.lightThemes.contains { $0.id == theme.id })
  }

  @Test("Catppuccin Latte status line follows Catppuccin nvim StatusLine palette")
  func catppuccinLatteStatusLineUsesPalette() {
    let status = ThemeCatalog.catppuccinLatte.statusLine
    #expect(status.trailingFill == Color(red: 0.902, green: 0.914, blue: 0.937))
    #expect(status.fileFill == Color(red: 0.863, green: 0.878, blue: 0.910))
    #expect(status.trailingText == Color(red: 0.361, green: 0.373, blue: 0.467))
    #expect(status.modeFill(for: .normal) == Color(red: 0.118, green: 0.400, blue: 0.961))
    #expect(status.modeText(for: .normal) == Color(red: 0.937, green: 0.945, blue: 0.961))
  }

  @Test("Rosé Pine Dawn status line follows rose-pine.nvim StatusLine palette")
  func rosePineDawnStatusLineUsesPalette() {
    let status = ThemeCatalog.rosePineDawn.statusLine
    #expect(status.trailingFill == Color(red: 1.000, green: 0.980, blue: 0.953))
    #expect(status.fileFill == Color(red: 0.949, green: 0.914, blue: 0.882))
    #expect(status.trailingText == Color(red: 0.475, green: 0.459, blue: 0.576))
    #expect(status.modeFill(for: .normal) == Color(red: 0.337, green: 0.580, blue: 0.624))
    #expect(status.modeText(for: .normal) == Color(red: 0.980, green: 0.957, blue: 0.929))
  }

  @Test("Catppuccin Latte cursor uses a peach accent")
  func catppuccinLatteCursorUsesPeachAccent() {
    #expect(ThemeCatalog.catppuccinLatte.cursor == Color(red: 0.996, green: 0.392, blue: 0.043))
  }

  @Test("Rosé Pine Dawn cursor uses a rose accent")
  func rosePineDawnCursorUsesRoseAccent() {
    #expect(ThemeCatalog.rosePineDawn.cursor == Color(red: 0.843, green: 0.510, blue: 0.494))
  }

  @Test("dark themes keep the original Ghostty-style off-white cursor")
  func darkThemesKeepOriginalCursor() {
    let originalCursor = Color(red: 0.973, green: 0.973, blue: 0.941)
    for theme in ThemeCatalog.darkThemes {
      #expect(theme.cursor == originalCursor, "\(theme.name) should keep the dark-theme cursor")
    }
  }

  @Test("light themes use visible dark or accent cursors")
  func lightThemesUseVisibleCursors() {
    #expect(ThemeCatalog.catppuccinLatte.cursor == Color(red: 0.996, green: 0.392, blue: 0.043))
    #expect(ThemeCatalog.rosePineDawn.cursor == Color(red: 0.843, green: 0.510, blue: 0.494))
    #expect(ThemeCatalog.bone.cursor == Color(red: 0.165, green: 0.165, blue: 0.165))
  }

  @Test("Catppuccin Latte Flash labels follow flash.nvim inline highlight colors")
  func catppuccinLatteFlashLabelsUseNvimInlineColors() {
    let flash = ThemeCatalog.catppuccinLatte.flash
    #expect(flash.backdropText == Color(red: 0.612, green: 0.627, blue: 0.690))
    #expect(flash.matchText == Color(red: 0.447, green: 0.529, blue: 0.992))
    #expect(flash.labelText == Color(red: 0.251, green: 0.627, blue: 0.169))
    #expect(flash.activeLabelText == Color(red: 0.996, green: 0.392, blue: 0.043))
  }

  @Test("Catppuccin Frappé Flash labels are bright on dark themes")
  func catppuccinFrappeFlashLabelsAreBrightOnDarkThemes() {
    let flash = ThemeCatalog.catppuccinFrappe.flash
    #expect(flash.backdropText == Color(red: 0.451, green: 0.475, blue: 0.580))
    #expect(flash.matchText == Color(red: 0.729, green: 0.733, blue: 0.945))
    #expect(flash.labelText == Color(red: 0.651, green: 0.820, blue: 0.537))
    #expect(flash.activeLabelText == Color(red: 0.937, green: 0.624, blue: 0.463))
  }

  @Test("Rosé Pine Dawn Flash labels use visible inline accent text")
  func rosePineDawnFlashLabelsUseVisibleInlineAccentText() {
    let flash = ThemeCatalog.rosePineDawn.flash
    #expect(flash.backdropText == Color(red: 0.596, green: 0.576, blue: 0.647))
    #expect(flash.matchText == Color(red: 0.565, green: 0.478, blue: 0.663))
    #expect(flash.labelText == Color(red: 0.427, green: 0.561, blue: 0.537))
    #expect(flash.activeLabelText == Color(red: 0.918, green: 0.616, blue: 0.204))
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

  @Test("catalog has exactly eight dark and seven light themes")
  func catalogSize() {
    #expect(ThemeCatalog.darkThemes.count == 8)
    #expect(ThemeCatalog.lightThemes.count == 7)
    #expect(ThemeCatalog.all.count == 15)
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

  @Test("maxVisibleLines defaults to 5 on first launch")
  func maxVisibleLinesDefault() {
    let prefs = ThemePreferences(defaults: makeDefaults())
    #expect(prefs.maxVisibleLines == ThemePreferences.defaultVisibleLines)
    #expect(prefs.maxVisibleLines == 5)
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
