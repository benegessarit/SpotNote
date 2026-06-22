import AppKit
import SwiftUI
import Testing

@testable import Spotlight

@MainActor
@Suite("Dark theme palette tokens")
struct DarkThemePaletteTests {
  private struct ExpectedThemeColors {
    let id: String
    let body: Color
    let heading: Color
  }

  @Test("dark themes carry explicit body and heading foreground colors")
  func darkThemeTextTokens() throws {
    let expected = expectedDarkThemeColors()
    #expect(ThemeCatalog.darkThemes.map(\.id) == expected.map(\.id))

    for row in expected {
      let theme = ThemeCatalog.theme(withID: row.id)
      let body = try #require(NSColor(theme.text).usingColorSpace(.sRGB))
      let expectedBody = try #require(NSColor(row.body).usingColorSpace(.sRGB))
      let heading = try #require(NSColor(theme.headingText).usingColorSpace(.sRGB))
      let expectedHeading = try #require(NSColor(row.heading).usingColorSpace(.sRGB))
      #expect(theme.mode == .dark, "\(row.id) should be dark")
      #expect(colorDistance(body, expectedBody) < 0.01, "\(row.id) body text")
      #expect(colorDistance(heading, expectedHeading) < 0.01, "\(row.id) heading text")
      #expect(colorDistance(heading, body) >= 0.08, "\(row.id) heading should be distinct from body")
    }
  }

  @Test("resolved cursor honors an explicit cursor and otherwise falls back to the heading accent")
  func resolvedCursorMatchesSpecOrFallsBackToAccent() throws {
    // Fahrenheit declares its official cursor (#bbbbbb); resolvedCursor must use it.
    let fahrenheitCursor = try #require(NSColor(ThemeCatalog.fahrenheit.resolvedCursor).usingColorSpace(.sRGB))
    let expectedCursor = try #require(NSColor(Color(testHex: 0xBBBBBB)).usingColorSpace(.sRGB))
    #expect(colorDistance(fahrenheitCursor, expectedCursor) < 0.01)

    // A theme with no explicit cursor falls back to its heading accent, so the
    // cursor tracks the theme instead of one global color.
    #expect(ThemeCatalog.mirage.cursor == nil)
    #expect(ThemeCatalog.mirage.resolvedCursor == ThemeCatalog.mirage.headingText)

    // Upstream-named themes pin their official cursor (verified against the
    // canonical palettes), not the heading accent.
    let officialCursors: [(String, UInt32)] = [
      ("catppuccin-mocha", 0xF5E0DC),  // Rosewater
      ("dracula", 0xF8F8F2),  // Foreground
      ("rose-pine-moonlight", 0x56526E)  // Highlight High
    ]
    for (id, hex) in officialCursors {
      let actual = try #require(NSColor(ThemeCatalog.theme(withID: id).resolvedCursor).usingColorSpace(.sRGB))
      let expected = try #require(NSColor(Color(testHex: hex)).usingColorSpace(.sRGB))
      #expect(colorDistance(actual, expected) < 0.01, "\(id) cursor should match its official spec")
    }
  }

  @Test("Markdown headings render with the selected theme heading color")
  func markdownHeadingsUseThemeHeadingColor() throws {
    let text = "plain\n## To Do\nnext"
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    textView.font = SpotNoteFont.editor()
    textView.string = text

    CodeStyler.apply(to: textView, theme: ThemeCatalog.dracula)

    let bodyColor = try #require(storageColor(at: 0, in: textView)?.usingColorSpace(.sRGB))
    let headingColor = try #require(
      storageColor(at: lineStart(1, in: text), in: textView)?.usingColorSpace(.sRGB)
    )
    let draculaBody = try #require(NSColor(ThemeCatalog.dracula.text).usingColorSpace(.sRGB))
    let draculaHeading = try #require(NSColor(ThemeCatalog.dracula.headingText).usingColorSpace(.sRGB))

    #expect(colorDistance(bodyColor, draculaBody) < 0.01)
    #expect(colorDistance(headingColor, draculaHeading) < 0.01)
  }

  private func expectedDarkThemeColors() -> [ExpectedThemeColors] {
    [
      ExpectedThemeColors(id: "fahrenheit", body: Color(testHex: 0xFFFFCE), heading: Color(testHex: 0xFD9F4D)),
      ExpectedThemeColors(id: "catppuccin-frappe", body: Color(testHex: 0xC6D0F5), heading: Color(testHex: 0xCA9EE6)),
      ExpectedThemeColors(id: "catppuccin-mocha", body: Color(testHex: 0xCDD6F4), heading: Color(testHex: 0xCBA6F7)),
      ExpectedThemeColors(id: "rose-pine-moonlight", body: Color(testHex: 0xE0DEF4), heading: Color(testHex: 0xC4A7E7)),
      ExpectedThemeColors(id: "ayu-mirage", body: Color(testHex: 0xCCCAC2), heading: Color(testHex: 0xFFCC66)),
      ExpectedThemeColors(id: "mirage", body: Color(testHex: 0xA6B2C0), heading: Color(testHex: 0xDDB3FF)),
      ExpectedThemeColors(id: "dracula", body: Color(testHex: 0xF8F8F2), heading: Color(testHex: 0xFF79C6)),
      ExpectedThemeColors(id: "nvim-dark", body: Color(testHex: 0xE0E2EA), heading: Color(testHex: 0xA6DBFF)),
      ExpectedThemeColors(id: "neobones-dark", body: Color(testHex: 0xC6D5CF), heading: Color(testHex: 0x92A0E2)),
      ExpectedThemeColors(id: "nightfox", body: Color(testHex: 0xCDCECF), heading: Color(testHex: 0x719CD6)),
      ExpectedThemeColors(id: "obsidian", body: Color(testHex: 0xE8E8ED), heading: Color(testHex: 0xD7C9FF)),
      ExpectedThemeColors(id: "ink", body: Color(testHex: 0xE2E8F0), heading: Color(testHex: 0x93C5FD)),
      ExpectedThemeColors(id: "graphite", body: Color(testHex: 0xD4D4D4), heading: Color(testHex: 0xE5E7EB)),
      ExpectedThemeColors(id: "midnight", body: Color(testHex: 0xD6DEEB), heading: Color(testHex: 0x7DD3FC)),
      ExpectedThemeColors(id: "charcoal", body: Color(testHex: 0xEBEBF0), heading: Color(testHex: 0xC4B5FD))
    ]
  }

  private func storageColor(at location: Int, in textView: NSTextView) -> NSColor? {
    textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
  }

  private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
    abs(lhs.redComponent - rhs.redComponent)
      + abs(lhs.greenComponent - rhs.greenComponent)
      + abs(lhs.blueComponent - rhs.blueComponent)
  }

  private func lineStart(_ index: Int, in text: String) -> Int {
    guard index > 0 else { return 0 }
    let lines = text.components(separatedBy: "\n")
    let prefix = lines.prefix(index).joined(separator: "\n")
    return (prefix as NSString).length + 1
  }
}

extension Color {
  init(testHex hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}
