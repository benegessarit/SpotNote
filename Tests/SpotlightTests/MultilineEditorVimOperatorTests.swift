import AppKit
import Testing

@testable import Spotlight

/// The operator applicator against a real text view: wise-ness, the
/// cw→ce swap, delete-yanks, and the iw/aw text objects. Each test
/// pins the vim-correct RESULT (David's nvim semantics), not the
/// mechanism.
@MainActor
extension MultilineEditorVimLogicalLineMotionTests {

  private func makeView(_ text: String, caret: Int) -> PlaceholderTextView {
    let textView = makeVimMotionTextView(text: text)
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("vim-operator-tests"))
    textView.vimPasteboard = pasteboard
    textView.setSelectedRange(NSRange(location: caret, length: 0))
    return textView
  }

  private func yanked(_ textView: PlaceholderTextView) -> String? {
    textView.vimPasteboard.string(forType: .string)
  }

  // MARK: - Charwise operators

  @Test("dw deletes the word and its trailing space, and yanks it")
  func dwDeletesAndYanks() {
    let textView = makeView("hello world", caret: 0)
    textView.applyVimOperator(.delete, to: .motion(.wordForward(1)))
    #expect(textView.string == "world")
    #expect(yanked(textView) == "hello ")
    #expect(textView.selectedRange.location == 0)
  }

  @Test("de deletes through the word's last character")
  func deIsInclusive() {
    let textView = makeView("hello world", caret: 0)
    textView.applyVimOperator(.delete, to: .motion(.wordEnd(1)))
    #expect(textView.string == " world")
  }

  @Test("cw acts as ce: the trailing space survives a change")
  func cwActsAsCE() {
    let textView = makeView("hello world", caret: 0)
    textView.applyVimOperator(.change, to: .motion(.wordForward(1)))
    #expect(textView.string == " world")
    #expect(yanked(textView) == "hello")
    #expect(textView.selectedRange.location == 0)
  }

  @Test("cw from whitespace keeps plain word-forward semantics")
  func cwFromWhitespace() {
    let textView = makeView("a  bc", caret: 1)
    textView.applyVimOperator(.change, to: .motion(.wordForward(1)))
    #expect(textView.string == "abc")
  }

  // MARK: - Linewise operators

  @Test("dj deletes both whole lines and yanks them linewise")
  func djIsLinewise() {
    let textView = makeView("alpha\nbravo\ncharlie", caret: 2)
    textView.applyVimOperator(.delete, to: .motion(.down(1)))
    #expect(textView.string == "charlie")
    #expect(yanked(textView) == "alpha\nbravo\n")
    #expect(textView.selectedRange.location == 0)
  }

  @Test("dk from the middle line takes it and the line above")
  func dkIsLinewise() {
    let textView = makeView("alpha\nbravo\ncharlie", caret: 8)
    textView.applyVimOperator(.delete, to: .motion(.up(1)))
    #expect(textView.string == "charlie")
  }

  @Test("dj on the last line aborts like vim")
  func djOnLastLineAborts() {
    let textView = makeView("alpha\nbravo", caret: 8)
    textView.applyVimOperator(.delete, to: .motion(.down(1)))
    #expect(textView.string == "alpha\nbravo")
  }

  @Test("dG deletes linewise from the caret's line to the end")
  func dGIsLinewise() {
    let textView = makeView("alpha\nbravo\ncharlie", caret: 8)
    textView.applyVimOperator(.delete, to: .motion(.documentEnd))
    #expect(textView.string == "alpha")
  }

  @Test("cj replaces both lines with one open empty line")
  func cjOpensEmptyLine() {
    let textView = makeView("alpha\nbravo\ncharlie", caret: 0)
    textView.applyVimOperator(.change, to: .motion(.down(1)))
    #expect(textView.string == "\ncharlie")
    #expect(textView.selectedRange.location == 0)
  }

  // MARK: - Yank

  @Test("yy yanks the line newline-terminated without mutating")
  func yyYanksLinewise() {
    let textView = makeView("alpha\nbravo", caret: 7)
    textView.executeYankLines(1)
    #expect(textView.string == "alpha\nbravo")
    #expect(yanked(textView) == "bravo\n")
    #expect(textView.selectedRange.location == 7)
  }

  @Test("yw yanks without mutating and keeps the caret at the span start")
  func ywYanks() {
    let textView = makeView("hello world", caret: 0)
    textView.applyVimOperator(.yank, to: .motion(.wordForward(1)))
    #expect(textView.string == "hello world")
    #expect(yanked(textView) == "hello ")
    #expect(textView.selectedRange.location == 0)
  }

  @Test("yb moves the caret back to the yanked span's start")
  func ybCaretToStart() {
    let textView = makeView("hello world", caret: 11)
    textView.applyVimOperator(.yank, to: .motion(.wordBackward(1)))
    #expect(textView.string == "hello world")
    #expect(textView.selectedRange.location == 6)
  }

  // MARK: - Text objects (pure)

  @Test("innerWord finds the keyword run around the caret")
  func innerWordKeyword() {
    let text = "hello world" as NSString
    #expect(VimTextObjects.innerWord(in: text, at: 8) == NSRange(location: 6, length: 5))
    #expect(VimTextObjects.innerWord(in: text, at: 0) == NSRange(location: 0, length: 5))
  }

  @Test("innerWord on whitespace selects the whitespace run")
  func innerWordWhitespace() {
    let text = "a   b" as NSString
    #expect(VimTextObjects.innerWord(in: text, at: 2) == NSRange(location: 1, length: 3))
  }

  @Test("innerWord treats punctuation as its own word class")
  func innerWordPunctuation() {
    let text = "foo(bar)" as NSString
    #expect(VimTextObjects.innerWord(in: text, at: 3) == NSRange(location: 3, length: 1))
  }

  @Test("innerWord never crosses a line boundary")
  func innerWordStopsAtNewline() {
    let text = "foo\nbar" as NSString
    #expect(VimTextObjects.innerWord(in: text, at: 3) == NSRange(location: 0, length: 3))
    #expect(VimTextObjects.innerWord(in: text, at: 4) == NSRange(location: 4, length: 3))
  }

  @Test("aroundWord takes the trailing whitespace, or leading when none trails")
  func aroundWordWhitespaceRules() {
    let text = "hello world" as NSString
    #expect(VimTextObjects.aroundWord(in: text, at: 1) == NSRange(location: 0, length: 6))
    #expect(VimTextObjects.aroundWord(in: text, at: 8) == NSRange(location: 5, length: 6))
  }

  // MARK: - Text objects (applied)

  @Test("ciw mid-word removes exactly the word")
  func ciwMidWord() {
    let textView = makeView("hello brave world", caret: 8)
    textView.applyVimOperator(.change, to: .innerWord)
    #expect(textView.string == "hello  world")
    #expect(yanked(textView) == "brave")
    #expect(textView.selectedRange.location == 6)
  }

  @Test("daw removes the word plus its trailing space")
  func dawTrailingSpace() {
    let textView = makeView("hello brave world", caret: 8)
    textView.applyVimOperator(.delete, to: .aroundWord)
    #expect(textView.string == "hello world")
  }

  @Test("full ciw keystroke path: c-i-w through the engine enters insert")
  func ciwKeystrokePath() {
    let textView = makeView("alpha beta", caret: 1)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.keyDown(with: keyEvent(characters: "c", ignoring: "c", keyCode: 8))
    textView.keyDown(with: keyEvent(characters: "i", ignoring: "i", keyCode: 34))
    textView.keyDown(with: keyEvent(characters: "w", ignoring: "w", keyCode: 13))
    #expect(textView.string == " beta")
    #expect(textView.vimEngine?.mode == .insert)
  }
}
