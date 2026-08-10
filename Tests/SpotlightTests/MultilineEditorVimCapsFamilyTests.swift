import AppKit
import Testing

@testable import Spotlight

/// View-level contracts for the caps/tilde editing family (C, Y, P, J,
/// X, ~, r) landed 2026-08-10 after David's "C doesn't work" report.
@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  private func armedCaps(_ text: String, caret: Int) -> PlaceholderTextView {
    let textView = makeVimMotionTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.vimPasteboard = NSPasteboard(name: NSPasteboard.Name("caps-family-tests"))
    textView.setSelectedRange(NSRange(location: caret, length: 0))
    return textView
  }

  @Test("C changes to end of line and lands in insert")
  func capCChangesToLineEnd() {
    let textView = armedCaps("alpha beta\nsecond", caret: 6)
    textView.keyDown(with: keyEvent(characters: "C", ignoring: "C", keyCode: 8, modifiers: [.shift]))
    #expect(textView.string == "alpha \nsecond")
    #expect(textView.vimEngine?.mode == .insert)
    // Like every change, C yanks what it removed.
    #expect(textView.vimPasteboard.string(forType: .string) == "beta")
  }

  @Test("Y yanks to end of line without touching the text")
  func capYYanksToLineEnd() {
    let textView = armedCaps("alpha beta\nsecond", caret: 6)
    textView.keyDown(with: keyEvent(characters: "Y", ignoring: "Y", keyCode: 16, modifiers: [.shift]))
    #expect(textView.string == "alpha beta\nsecond")
    #expect(textView.vimPasteboard.string(forType: .string) == "beta")
    #expect(textView.vimEngine?.mode == .normal)
  }

  @Test("P pastes charwise before the caret")
  func capPPastesCharwiseBefore() {
    let textView = armedCaps("ad", caret: 1)
    textView.vimPasteboard.clearContents()
    textView.vimPasteboard.setString("bc", forType: .string)
    textView.executeVimAction(.pasteBefore(count: 1))
    #expect(textView.string == "abcd")
    // Caret rests on the LAST pasted char, like vim.
    #expect(textView.selectedRange == NSRange(location: 2, length: 0))
  }

  @Test("P pastes linewise above the current line")
  func capPPastesLinewiseAbove() {
    let textView = armedCaps("one\ntwo\n", caret: 5)
    textView.vimPasteboard.clearContents()
    textView.vimPasteboard.setString("zero\n", forType: .string)
    textView.executeVimAction(.pasteBefore(count: 1))
    #expect(textView.string == "one\nzero\ntwo\n")
    #expect(textView.selectedRange == NSRange(location: 4, length: 0))
  }

  @Test("J joins the next line up with a single space, eating its indent")
  func joinEatsIndent() {
    let textView = armedCaps("alpha\n   beta\n", caret: 2)
    textView.executeVimAction(.joinLines(count: 1))
    #expect(textView.string == "alpha beta\n")
    // Caret sits on the join space.
    #expect(textView.selectedRange == NSRange(location: 5, length: 0))
  }

  @Test("3J joins three lines")
  func countedJoin() {
    let textView = armedCaps("a\nb\nc\nd", caret: 0)
    textView.executeVimAction(.joinLines(count: 3))
    #expect(textView.string == "a b c\nd")
  }

  @Test("J on the last line is a no-op")
  func joinLastLineNoop() {
    let textView = armedCaps("only", caret: 2)
    textView.executeVimAction(.joinLines(count: 1))
    #expect(textView.string == "only")
  }

  @Test("tilde toggles case and advances, stopping at the line end")
  func tildeTogglesAndAdvances() {
    let textView = armedCaps("aB\nrest", caret: 0)
    textView.executeVimAction(.toggleCase(count: 5))
    #expect(textView.string == "Ab\nrest")
    // Clamped at the line end -- never wraps onto the next line.
    #expect(textView.selectedRange == NSRange(location: 2, length: 0))
  }

  @Test("r replaces count chars and aborts when the line runs out")
  func replaceCharRespectsLineEnd() {
    let textView = armedCaps("abcd\nnext", caret: 1)
    textView.executeVimAction(.replaceChar("x", count: 2))
    #expect(textView.string == "axxd\nnext")
    // Caret on the LAST replacement.
    #expect(textView.selectedRange == NSRange(location: 2, length: 0))
    // 9 chars don't fit before the line end: vim aborts wholesale.
    textView.executeVimAction(.replaceChar("z", count: 9))
    #expect(textView.string == "axxd\nnext")
  }

  @Test("X deletes backward, clamped to the line start")
  func deleteBackClampsAtLineStart() {
    let textView = armedCaps("ab\ncdef", caret: 5)
    textView.executeVimAction(.deleteCharBefore(count: 4))
    // Only "cd" precede the caret on this line; the newline survives.
    #expect(textView.string == "ab\nef")
    #expect(textView.selectedRange == NSRange(location: 3, length: 0))
  }
}
