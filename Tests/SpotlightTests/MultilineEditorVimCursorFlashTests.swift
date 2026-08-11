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

  @Test("M-j swaps the caret line with the line below, caret riding along")
  func moveLineDownSwaps() {
    let textView = armedFlash("alpha\nbeta\ngamma", caret: 2)
    textView.executeVimAction(.moveLinesDown(count: 1))
    #expect(textView.string == "beta\nalpha\ngamma")
    // Caret stays on "alpha" (now line 2), column preserved.
    #expect(textView.selectedRange == NSRange(location: 7, length: 0))
  }

  @Test("M-k moves the tail line up even without a trailing newline")
  func moveTailLineUp() {
    let textView = armedFlash("alpha\nbeta", caret: 8)
    textView.executeVimAction(.moveLinesUp(count: 1))
    #expect(textView.string == "beta\nalpha")
    #expect(textView.selectedRange == NSRange(location: 2, length: 0))
  }

  @Test("line moves clamp silently at the buffer edges")
  func moveLinesClampsAtEdges() {
    let top = armedFlash("alpha\nbeta", caret: 0)
    top.executeVimAction(.moveLinesUp(count: 1))
    #expect(top.string == "alpha\nbeta")

    let bottom = armedFlash("alpha\nbeta", caret: 7)
    bottom.executeVimAction(.moveLinesDown(count: 3))
    #expect(bottom.string == "alpha\nbeta")
  }

  @Test("a count moves the line several steps, stopping at the edge")
  func moveLinesHonorsCount() {
    let textView = armedFlash("alpha\nbeta\ngamma", caret: 0)
    textView.executeVimAction(.moveLinesDown(count: 5))
    #expect(textView.string == "beta\ngamma\nalpha")
  }

  @Test("visual line M-j moves the selected block and keeps the selection")
  func visualLineBlockMoves() {
    let textView = armedFlash("alpha\nbeta\ngamma\n", caret: 0)
    textView.keyDown(with: keyEvent(characters: "V", ignoring: "V", keyCode: 9, modifiers: [.shift]))
    textView.keyDown(with: keyEvent(characters: "j", ignoring: "j", keyCode: 38, modifiers: []))
    #expect(textView.selectedRange == NSRange(location: 0, length: 11))
    textView.executeVimAction(.moveLinesDown(count: 1))
    #expect(textView.string == "gamma\nalpha\nbeta\n")
    // Selection still covers the alpha/beta block, mode still visual line.
    #expect(textView.selectedRange == NSRange(location: 6, length: 11))
    #expect(textView.vimEngine?.mode == .visualLine)
  }

  @Test("option-j reaches the engine as the mini.move token")
  func optionKeyBecomesMetaToken() {
    let textView = armedFlash("alpha\nbeta", caret: 0)
    textView.keyDown(
      with: keyEvent(characters: "\u{2206}", ignoring: "j", keyCode: 38, modifiers: [.option])
    )
    #expect(textView.string == "beta\nalpha")
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
