import AppKit
import Testing

@testable import Spotlight

/// nvim-parity contracts for the rebuilt visual mode: the coherence
/// repair (no stale half-visual state after ANY exit path), the
/// no-clobber visual paste, o/gv, absolute <n>G, the block cursor, and
/// the flat nvim-style selection color.
@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  private func armedVisual(_ text: String, caret: Int) -> PlaceholderTextView {
    let textView = makeVimMotionTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.vimPasteboard = NSPasteboard(name: NSPasteboard.Name("visual-nvim-tests"))
    textView.setSelectedRange(NSRange(location: caret, length: 0))
    return textView
  }

  private func press(_ textView: PlaceholderTextView, _ ch: String, _ code: UInt16, shift: Bool = false) {
    textView.keyDown(
      with: keyEvent(
        characters: ch,
        ignoring: ch,
        keyCode: code,
        modifiers: shift ? [.shift] : []
      )
    )
  }

  @Test("visual o swaps the moving end and the anchor")
  func visualSwapEndsMovesTheOtherSide() {
    let textView = armedVisual("alpha beta gamma", caret: 6)
    press(textView, "v", 9)
    press(textView, "e", 14)  // select "beta"
    let before = textView.selectedRange
    press(textView, "o", 31)
    #expect(textView.selectedRange == before)
    #expect(textView.visualAnchor ?? -1 > (textView.visualCaret ?? -1))
    press(textView, "b", 11)  // now extends the LEFT side
    #expect(textView.selectedRange.location == 0)
  }

  @Test("visual p replaces the selection and never clobbers the register")
  func visualPasteKeepsRegister() {
    let textView = armedVisual("alpha beta", caret: 0)
    textView.vimPasteboard.clearContents()
    textView.vimPasteboard.setString("NEW", forType: .string)
    press(textView, "v", 9)
    press(textView, "e", 14)  // select "alpha"
    press(textView, "p", 35)
    #expect(textView.string == "NEW beta")
    #expect(textView.vimPasteboard.string(forType: .string) == "NEW")
    #expect(textView.vimEngine?.mode == .normal)
    #expect(textView.visualAnchor == nil)
  }

  @Test("gv reselects the last visual range after an escape")
  func gvReselectsAfterEscape() {
    let textView = armedVisual("alpha beta", caret: 0)
    press(textView, "v", 9)
    press(textView, "e", 14)
    let selected = textView.selectedRange
    press(textView, "\u{1B}", 53)
    #expect(textView.selectedRange.length == 0)
    press(textView, "g", 5)
    press(textView, "v", 9)
    #expect(textView.vimEngine?.mode == .visual)
    #expect(textView.selectedRange == selected)
  }

  @Test("visual <n>G snaps to the absolute line, not a relative walk")
  func visualCountedGIsAbsolute() {
    let textView = armedVisual("one\ntwo\nthree\nfour", caret: 4)  // caret on line 2
    press(textView, "V", 9, shift: true)
    press(textView, "3", 20)
    press(textView, "G", 5, shift: true)
    // Lines 2..3 selected ("two\nthree\n"), NOT 2..(2+2).
    #expect(textView.selectedRange == NSRange(location: 4, length: 10))
  }

  @Test("a leader handoff leaving visual mode cannot strand anchors")
  func coherenceRepairClearsStrandedAnchors() {
    let textView = armedVisual("alpha beta", caret: 0)
    press(textView, "v", 9)
    press(textView, "e", 14)
    // Force the desync shape directly: the engine leaves visual while
    // the view still holds anchors (the leader-handoff class).
    _ = textView.vimEngine?.handle(key: "\u{1B}", hasModifiers: false)
    textView.executeVimAction(.none)
    #expect(textView.visualAnchor == nil)
    #expect(textView.visualCaret == nil)
    #expect(textView.selectedRange.length == 0)
    // The abandoned range is still reachable via gv.
    #expect(textView.lastVisualRange != nil)
  }

  @Test("visual mode draws a block cursor at the moving end")
  func visualBlockCursorExists() {
    let textView = armedVisual("alpha beta", caret: 0)
    press(textView, "v", 9)
    press(textView, "e", 14)
    let rect = textView.visualBlockCursorRect()
    #expect(rect != nil)
    #expect((rect?.width ?? 0) > 2)
    press(textView, "\u{1B}", 53)
    #expect(textView.visualBlockCursorRect() == nil)
  }

  @Test("the selection color is the flat background-to-text lift, not accent blue")
  func selectionColorIsNvimVisual() throws {
    let textView = makeVimMotionTextView(text: "alpha")
    let bg = try #require(
      (textView.selectedTextAttributes[.backgroundColor] as? NSColor)?
        .usingColorSpace(.deviceRGB)
    )
    let theme = ThemeCatalog.obsidian
    let base = try #require(NSColor(theme.background).usingColorSpace(.deviceRGB))
    let text = try #require(NSColor(theme.text).usingColorSpace(.deviceRGB))
    // 11% on dark: nvim's RELATIONSHIP (surface->text blend, no accent
    // hue) at David's stronger depth ("still not really visible" at the
    // probed 5%, 2026-08-11).
    let expectedRed = base.redComponent + 0.11 * (text.redComponent - base.redComponent)
    // 0.05 tolerance: blended() works in a calibrated space and the
    // deviceRGB readback drift grows with the fraction -- still far
    // tighter than the ~0.09 gap back to the 5% blend.
    #expect(abs(bg.redComponent - expectedRed) < 0.05)
    // Still a neutral lift: blue moves by the same fraction toward the
    // text ink, nowhere near the system accent's saturation.
    let expectedBlue = base.blueComponent + 0.11 * (text.blueComponent - base.blueComponent)
    #expect(abs(bg.blueComponent - expectedBlue) < 0.05)
  }
}
