import AppKit
import Testing

@testable import Spotlight

/// Contracts for the round of David's 2026-08-10 theme/feel report: the
/// rosewater block cursor, the view-owned visual band, the yank flash,
/// and the code-styler typing hot path.
@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  private func armedFlash(_ text: String, caret: Int) -> PlaceholderTextView {
    let textView = makeVimMotionTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.vimPasteboard = NSPasteboard(name: NSPasteboard.Name("cursor-flash-tests"))
    textView.editorVisualSelectionColor = NSColor(white: 0.2, alpha: 1)
    textView.setSelectedRange(NSRange(location: caret, length: 0))
    return textView
  }

  @Test("vim block cursor is the rosewater role, never the caret red or accent")
  func blockCursorIsRosewater() throws {
    let dark = try #require(
      NSColor(ThemeCatalog.raycastDark.vimBlockCursor).usingColorSpace(.sRGB)
    )
    #expect(abs(dark.redComponent - 0xF5 / 255) < 0.01)
    #expect(abs(dark.greenComponent - 0xE0 / 255) < 0.01)
    #expect(abs(dark.blueComponent - 0xDC / 255) < 0.01)
    let light = try #require(
      NSColor(ThemeCatalog.porcelain.vimBlockCursor).usingColorSpace(.sRGB)
    )
    #expect(abs(light.redComponent - 0xDC / 255) < 0.01)
    #expect(abs(light.greenComponent - 0x8A / 255) < 0.01)
    #expect(abs(light.blueComponent - 0x78 / 255) < 0.01)
  }

  @Test("applyVisualSelectionColor hands the view its own band color")
  func visualBandColorReachesView() throws {
    let textView = armedFlash("alpha", caret: 0)
    textView.editorVisualSelectionColor = nil
    CodeStyler.applyVisualSelectionColor(to: textView, theme: ThemeCatalog.raycastDark)
    let band = try #require(textView.editorVisualSelectionColor)
    let native = try #require(
      textView.selectedTextAttributes[.backgroundColor] as? NSColor
    )
    #expect(band == native)
  }

  @Test("yy flashes the yanked line with the Visual band")
  func yankLinesFlashes() {
    let textView = armedFlash("alpha\nbeta", caret: 2)
    textView.executeVimAction(.yankLine(count: 1))
    #expect(textView.yankFlashRange == NSRange(location: 0, length: 6))
    #expect(textView.yankFlashAlpha == 1)
  }

  @Test("operator yank flashes its span; delete does not flash")
  func operatorYankFlashes() {
    let yanked = armedFlash("alpha beta", caret: 0)
    yanked.executeVimAction(.applyOperator(.yank, .motion(.wordForward(1))))
    #expect(yanked.yankFlashRange == NSRange(location: 0, length: 6))

    let deleted = armedFlash("alpha beta", caret: 0)
    deleted.executeVimAction(.applyOperator(.delete, .motion(.wordForward(1))))
    #expect(deleted.yankFlashRange == nil)
  }

  @Test("an edit clears a live yank flash")
  func editClearsFlash() {
    let textView = armedFlash("alpha\nbeta", caret: 0)
    textView.executeVimAction(.yankLine(count: 1))
    #expect(textView.yankFlashRange != nil)
    textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
    #expect(textView.yankFlashRange == nil)
  }

  @Test("code styler skips the full clear while the note has no backticks")
  func codeStylerSkipsPlainNotes() {
    let textView = armedFlash("plain text with words", caret: 0)
    guard let layoutManager = textView.layoutManager else {
      Issue.record("missing layout manager")
      return
    }
    // First pass on plain text: does the full clear, then arms the skip.
    CodeStyler.apply(to: textView, theme: ThemeCatalog.raycastDark)
    #expect(textView.codeStylerLeftAttributes == false)
    // With the skip armed, a stray temporary attribute SURVIVES apply()
    // -- the hot path never touches the layout.
    let probe = NSRange(location: 0, length: 5)
    layoutManager.addTemporaryAttribute(
      .backgroundColor,
      value: NSColor.red,
      forCharacterRange: probe
    )
    CodeStyler.apply(to: textView, theme: ThemeCatalog.raycastDark)
    var effective = NSRange()
    let survived = layoutManager.temporaryAttribute(
      .backgroundColor,
      atCharacterIndex: 0,
      effectiveRange: &effective
    )
    #expect(survived != nil)
    // Backticks disarm the skip and the full pass clears again.
    textView.string = "now with `code` inside"
    CodeStyler.apply(to: textView, theme: ThemeCatalog.raycastDark)
    #expect(textView.codeStylerLeftAttributes == true)
  }
}
