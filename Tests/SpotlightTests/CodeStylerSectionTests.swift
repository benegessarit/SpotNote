import AppKit
import SwiftUI
import Testing

@testable import Spotlight

@MainActor
@Suite("CodeStyler Markdown section styling")
struct CodeStylerSectionTests {
  @Test("TRAY section body text is slightly dimmed")
  func traySectionBodyTextIsSlightlyDimmed() throws {
    let theme = ThemeCatalog.mirage
    let text = "## TODO\n- active\n\n## TRAY\n- parked\nplain\n\n## Notes\n- normal"
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 260))
    textView.font = SpotNoteFont.editor()
    textView.string = text

    CodeStyler.apply(to: textView, theme: theme)

    let todoBody = try #require(
      storageColor(at: lineStart(1, in: text) + 2, in: textView)?.usingColorSpace(.sRGB)
    )
    let trayHeading = try #require(
      storageColor(at: lineStart(3, in: text), in: textView)?.usingColorSpace(.sRGB)
    )
    let trayBody = try #require(
      storageColor(at: lineStart(4, in: text) + 2, in: textView)?.usingColorSpace(.sRGB)
    )
    let normalBody = try #require(
      storageColor(at: lineStart(8, in: text) + 2, in: textView)?.usingColorSpace(.sRGB)
    )
    let expectedHeading = try #require(NSColor(theme.headingText).usingColorSpace(.sRGB))

    #expect(colorDistance(trayHeading, expectedHeading) < 0.01)
    #expect(trayBody.alphaComponent < todoBody.alphaComponent)
    #expect(trayBody.alphaComponent > 0.70)
    #expect(normalBody.alphaComponent == todoBody.alphaComponent)
    #expect(textView.textStorage?.string == text)
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
