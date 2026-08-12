import AppKit
import Testing

@testable import Spotlight

/// Prompt-lane guards from the 2026-08-11 review-fix batch: modifier
/// chords are swallowed while any prompt is open (never falling through
/// to the vim engine), Ctrl-C aborts like Escape, Enter preserves the
/// stashed pattern, n/N anchor to the caret, and the extension set sees
/// overlapping occurrences. Uses the `armedSearch`/`type` harness from
/// MultilineEditorVimSearchTests.
@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  @Test("overlapping occurrences feed the extension set so labels never shadow them")
  func coreOverlappingExtensionCharacters() {
    let text = "aaas"
    // The drawn (non-overlapping) scan records only (0,2); the skipped
    // (1,2) occurrence is followed by "s" -- typing "s" must extend to
    // search "aas", never label-jump.
    let extending = VimSearchCore.extensionCharacters(of: "aa", in: text)
    #expect(extending == Set("as"))
    #expect(!VimSearchCore.survivingKeys(query: "aa", text: text).contains("s"))
  }

  @Test("option chords are swallowed by the / prompt, never edit the note")
  func optionChordSwallowedInSearchPrompt() {
    let (textView, controller) = armedSearch("alpha\nbeta", caret: 0)
    type(textView, "/")
    type(textView, "b")
    type(textView, "\r", keyCode: 36)
    type(textView, "/")
    type(textView, "a")
    // ⌥J is mini.move's line swap when it reaches the vim engine.
    textView.keyDown(
      with: keyEvent(characters: "∆", ignoring: "j", keyCode: 38, modifiers: .option)
    )
    #expect(textView.string == "alpha\nbeta")
    #expect(controller.prompt?.buffer == "a")
    #expect(!textView.vimSearchMatches.isEmpty)
    // The parked previous search survived the swallowed chord.
    #expect(textView.vimSearchStash != nil)
  }

  @Test("option chords are swallowed by the : prompt, never edit the note")
  func optionChordSwallowedInCommandPrompt() {
    let (textView, controller) = armedSearch("alpha\nbeta", caret: 0)
    type(textView, ":")
    type(textView, "s")
    textView.keyDown(
      with: keyEvent(characters: "∆", ignoring: "j", keyCode: 38, modifiers: .option)
    )
    #expect(textView.string == "alpha\nbeta")
    #expect(controller.prompt?.buffer == "s")
  }

  @Test("option chords are swallowed by the flash prompt, never edit the note")
  func optionChordSwallowedInFlashPrompt() {
    let (textView, controller) = armedSearch("alpha\nbeta", caret: 0)
    type(textView, "f")
    #expect(controller.prompt != nil)
    textView.keyDown(
      with: keyEvent(characters: "∆", ignoring: "j", keyCode: 38, modifiers: .option)
    )
    #expect(textView.string == "alpha\nbeta")
    #expect(controller.prompt != nil)
  }

  @Test("Ctrl-C aborts the / prompt exactly like Escape, keeping the previous search")
  func controlCAbortsSearchPrompt() {
    let (textView, controller) = armedSearch("alpha beta alpha", caret: 0)
    type(textView, "/")
    type(textView, "b")
    type(textView, "\r", keyCode: 36)
    #expect(textView.selectedRange.location == 6)
    type(textView, "/")
    type(textView, "x")
    textView.keyDown(
      with: keyEvent(characters: "\u{03}", ignoring: "c", keyCode: 8, modifiers: .control)
    )
    #expect(controller.prompt == nil)
    #expect(textView.vimSearchQuery == "b")
    #expect(textView.vimSearchCommitted == true)
    #expect(textView.selectedRange.location == 6)
    #expect(controller.searchStatus == "1/1")
  }

  @Test("Ctrl-C aborts the : prompt")
  func controlCAbortsCommandPrompt() {
    let (textView, controller) = armedSearch("alpha", caret: 0)
    type(textView, ":")
    type(textView, "w")
    textView.keyDown(
      with: keyEvent(characters: "\u{03}", ignoring: "c", keyCode: 8, modifiers: .control)
    )
    #expect(controller.prompt == nil)
    #expect(textView.string == "alpha")
  }

  @Test("n steps from the caret, not the last jump: G then n finds the next match forward")
  func stepAnchorsToCaret() {
    let (textView, controller) = armedSearch("alpha\nbeta\ngamma", caret: 0)
    type(textView, "/")
    type(textView, "a")
    type(textView, "\r", keyCode: 36)
    #expect(textView.selectedRange.location == 0)
    type(textView, "G")
    #expect(textView.selectedRange.location == 16)
    // Index-anchored stepping would jump BACKWARD to offset 4 here
    // (stale current + 1); vim searches from the cursor and wraps to
    // the top.
    type(textView, "n")
    #expect(textView.selectedRange.location == 0)
    #expect(controller.searchStatus == "1/5")
    type(textView, "n")
    #expect(textView.selectedRange.location == 4)
    #expect(controller.searchStatus == "2/5")
    type(textView, "N")
    #expect(textView.selectedRange.location == 0)
    #expect(controller.searchStatus == "1/5")
  }

  @Test("Enter on an empty / repeats the previous search from the caret")
  func emptyEnterRepeatsPreviousSearch() {
    let (textView, controller) = armedSearch("alpha beta alpha", caret: 0)
    type(textView, "/")
    type(textView, "a")
    type(textView, "l")
    type(textView, "\r", keyCode: 36)
    #expect(textView.selectedRange.location == 0)
    // Move the caret strictly between the two matches: the repeat must
    // land on the NEXT one, not step off the stale match index.
    type(textView, "w")
    #expect(textView.selectedRange.location == 6)
    type(textView, "/")
    #expect(textView.vimSearchCommitted == false)
    type(textView, "\r", keyCode: 36)
    #expect(controller.prompt == nil)
    #expect(textView.vimSearchQuery == "al")
    #expect(textView.vimSearchCommitted == true)
    #expect(textView.selectedRange.location == 11)
    #expect(controller.searchStatus == "2/2")
  }

  @Test("Enter on a no-match / keeps the previous pattern and reports the failure")
  func noMatchEnterKeepsPreviousSearch() {
    let (textView, controller) = armedSearch("alpha beta alpha", caret: 0)
    type(textView, "/")
    type(textView, "b")
    type(textView, "\r", keyCode: 36)
    #expect(textView.selectedRange.location == 6)
    type(textView, "/")
    type(textView, "z")
    type(textView, "z")
    type(textView, "\r", keyCode: 36)
    #expect(controller.prompt == nil)
    #expect(textView.vimSearchQuery == "b")
    #expect(textView.vimSearchCommitted == true)
    #expect(textView.selectedRange.location == 6)
    #expect(controller.message?.kind == .error)
    type(textView, "n")
    #expect(controller.searchStatus == "1/1")
  }

  @Test("empty Enter repeats from where / opened, not the incsearch-drifted caret")
  func emptyEnterRepeatsFromPromptOrigin() {
    let (textView, controller) = armedSearch("aa x b aa", caret: 0)
    type(textView, "/")
    type(textView, "a")
    type(textView, "a")
    type(textView, "\r", keyCode: 36)
    type(textView, "n")
    #expect(textView.selectedRange.location == 7)
    type(textView, "/")
    type(textView, "b")
    // incsearch parks the caret on the dead query's match at 5...
    #expect(textView.selectedRange.location == 5)
    type(textView, "\u{08}", keyCode: 51)
    type(textView, "\r", keyCode: 36)
    // ...but vim's cursor never moved: the repeat steps from 7 and
    // wraps to the top. A drift-anchored repeat would land on 7 again.
    #expect(textView.selectedRange.location == 0)
    #expect(controller.searchStatus == "1/2")
  }

  @Test("Enter on an empty / with no previous search reports instead of committing")
  func emptyEnterWithoutStashReports() {
    let (textView, controller) = armedSearch("alpha", caret: 0)
    type(textView, "/")
    type(textView, "\r", keyCode: 36)
    #expect(controller.prompt == nil)
    #expect(textView.vimSearchCommitted == false)
    #expect(controller.message?.kind == .error)
  }
}
