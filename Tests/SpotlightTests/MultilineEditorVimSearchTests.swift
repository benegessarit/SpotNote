import AppKit
import Testing

@testable import Spotlight

/// Contracts for `/` flash-search (the port of David's flash.nvim
/// search integration): live incremental matching, the extend-vs-label
/// resolution, label jumps, Enter commit + n/N, Escape restore, `*`,
/// and the prompt capsule surface.
@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  private func armedSearch(_ text: String, caret: Int) -> (PlaceholderTextView, VimController) {
    let textView = makeVimMotionTextView(text: text)
    textView.vimModeEnabled = true
    let controller = VimController()
    textView.attachVimController(controller)
    CodeStyler.applyVisualSelectionColor(to: textView, theme: ThemeCatalog.raycastDark)
    textView.setSelectedRange(NSRange(location: caret, length: 0))
    return (textView, controller)
  }

  private func type(_ textView: PlaceholderTextView, _ chars: String, keyCode: UInt16 = 0) {
    textView.keyDown(with: keyEvent(characters: chars, ignoring: chars, keyCode: keyCode))
  }

  // MARK: - Pure core

  @Test("live matching is literal, case-insensitive, and capped")
  func coreMatchesAndCap() {
    let (ranges, capped) = VimSearchCore.matches(of: "ab", in: "AB xab Ab")
    #expect(
      ranges == [
        NSRange(location: 0, length: 2),
        NSRange(location: 4, length: 2),
        NSRange(location: 7, length: 2)
      ]
    )
    #expect(capped == false)
    let big = String(repeating: "a", count: VimSearchCore.matchCap + 40)
    let (capRanges, capFlag) = VimSearchCore.matches(of: "a", in: big)
    #expect(capRanges.count == VimSearchCore.matchCap)
    #expect(capFlag == true)
  }

  @Test("current match is the first at/after the caret, wrapping to the top")
  func coreCurrentIndexWraps() {
    let matches = [NSRange(location: 2, length: 1), NSRange(location: 9, length: 1)]
    #expect(VimSearchCore.currentIndex(matches: matches, caret: 0) == 0)
    #expect(VimSearchCore.currentIndex(matches: matches, caret: 3) == 1)
    #expect(VimSearchCore.currentIndex(matches: matches, caret: 10) == 0)
    #expect(VimSearchCore.currentIndex(matches: [], caret: 0) == nil)
  }

  @Test("label alphabet excludes every character that could extend the query")
  func coreSurvivingKeys() {
    let text = "sat sam sax"
    let (matches, _) = VimSearchCore.matches(of: "sa", in: text)
    let extending = VimSearchCore.extensionCharacters(matches: matches, text: text)
    #expect(extending == Set("tmx"))
    let surviving = VimSearchCore.survivingKeys(matches: matches, text: text)
    #expect(!surviving.contains("t"))
    #expect(!surviving.contains("m"))
    #expect(!surviving.contains("x"))
    #expect(surviving.contains("a"))
  }

  @Test("labels stay single-character on overflow: nearest matches labeled, rest band-only")
  func coreLabelPlanOverflowCap() {
    let matches = (0..<40).map { NSRange(location: $0 * 5, length: 1) }
    let keys: [Character] = ["s", "d", "f"]
    let plan = VimSearchCore.labelPlan(matches: matches, caret: 52, keys: keys)
    #expect(plan.count == 3)
    // Nearest the caret first: match index 10 (at 50), then 11 (55), 9 (45).
    #expect(plan[0] == VimSearchLabelPlan(label: "s", matchIndex: 10))
    #expect(plan[1].matchIndex == 11)
    #expect(plan[2].matchIndex == 9)
  }

  // MARK: - Live prompt

  @Test("typing after / searches live: bands, caret ride, counter")
  func liveIncrementalSearch() {
    let (textView, controller) = armedSearch("alpha beta gamma", caret: 6)
    type(textView, "/")
    #expect(controller.prompt?.kind == .search)
    type(textView, "g")
    #expect(controller.prompt?.buffer == "g")
    #expect(textView.vimSearchMatches == [NSRange(location: 11, length: 1)])
    #expect(textView.selectedRange == NSRange(location: 11, length: 0))
    #expect(controller.searchStatus == "1/1")
  }

  @Test("a character that could extend the query extends it, never label-jumps")
  func extendBeatsLabel() {
    let (textView, controller) = armedSearch("sat sam sax", caret: 0)
    type(textView, "/")
    type(textView, "s")
    type(textView, "a")
    #expect(controller.prompt?.buffer == "sa")
    #expect(textView.vimSearchMatches.count == 3)
    // "t" extends (sat exists) even though it is also low in the charset.
    type(textView, "t")
    #expect(controller.prompt?.buffer == "sat")
    #expect(textView.vimSearchMatches == [NSRange(location: 0, length: 3)])
  }

  @Test("a non-extending label character jumps, commits for n/N, and darkens bands")
  func labelJumpCommits() {
    let (textView, controller) = armedSearch("alpha beta gamma", caret: 0)
    type(textView, "/")
    type(textView, "t")
    // One match ("t" in beta at 8); next char is "a" so "a" is excluded;
    // the nearest label is "s".
    #expect(textView.vimSearchLabelPlans.first?.label == "s")
    type(textView, "s")
    #expect(controller.prompt == nil)
    #expect(textView.selectedRange == NSRange(location: 8, length: 0))
    #expect(textView.vimSearchCommitted == true)
    #expect(textView.vimSearchBandsVisible == false)
    // n re-lights the highlight and steps (single match: stays).
    type(textView, "n")
    #expect(textView.vimSearchBandsVisible == true)
    #expect(controller.searchStatus == "1/1")
  }

  @Test("Escape cancels: caret and state restored, counter cleared")
  func escapeRestoresOrigin() {
    let (textView, controller) = armedSearch("alpha beta gamma", caret: 12)
    type(textView, "/")
    type(textView, "b")
    #expect(textView.selectedRange.location != 12)
    type(textView, "\u{1B}", keyCode: 53)
    #expect(controller.prompt == nil)
    #expect(textView.selectedRange == NSRange(location: 12, length: 0))
    #expect(textView.vimSearchMatches.isEmpty)
    #expect(controller.searchStatus == nil)
  }

  @Test("Enter commits: bands persist and n/N cycle with wrap")
  func enterCommitsAndSteps() {
    let (textView, controller) = armedSearch("alpha beta gamma", caret: 0)
    type(textView, "/")
    type(textView, "a")
    #expect(controller.searchStatus == "1/5")
    type(textView, "\r", keyCode: 36)
    #expect(controller.prompt == nil)
    #expect(textView.vimSearchCommitted == true)
    #expect(textView.vimSearchBandsVisible == true)
    type(textView, "n")
    #expect(textView.selectedRange == NSRange(location: 4, length: 0))
    #expect(controller.searchStatus == "2/5")
    type(textView, "N")
    #expect(controller.searchStatus == "1/5")
    type(textView, "N")
    #expect(controller.searchStatus == "5/5")
  }

  @Test("an edit clears the committed search")
  func editClearsSearch() {
    let (textView, controller) = armedSearch("alpha beta", caret: 0)
    type(textView, "/")
    type(textView, "a")
    type(textView, "\r", keyCode: 36)
    #expect(!textView.vimSearchMatches.isEmpty)
    textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
    #expect(textView.vimSearchMatches.isEmpty)
    #expect(textView.vimSearchCommitted == false)
    #expect(controller.searchStatus == nil)
  }

  @Test("* searches the word under the caret, landing on the next occurrence")
  func starSearchesWordUnderCaret() {
    let (textView, controller) = armedSearch("beta x beta", caret: 1)
    type(textView, "*")
    #expect(textView.vimSearchQuery == "beta")
    #expect(textView.selectedRange == NSRange(location: 7, length: 0))
    #expect(controller.searchStatus == "2/2")
    #expect(textView.vimSearchCommitted == true)
    #expect(textView.vimSearchBandsVisible == true)
  }

  @Test("n without a search reports instead of crashing")
  func stepWithoutSearchReports() {
    let (textView, controller) = armedSearch("alpha", caret: 0)
    type(textView, "n")
    #expect(controller.message?.kind == .error)
  }

  @Test(":noh hides bands but keeps the query; n re-lights")
  func nohKeepsQuery() {
    let (textView, controller) = armedSearch("alpha beta", caret: 0)
    type(textView, "/")
    type(textView, "b")
    type(textView, "\r", keyCode: 36)
    textView.dismissVimSearchHighlight()
    #expect(textView.vimSearchBandsVisible == false)
    #expect(textView.vimSearchCommitted == true)
    #expect(controller.searchStatus == nil)
    type(textView, "n")
    #expect(textView.vimSearchBandsVisible == true)
  }

  @Test("live labels hide the glyphs they cover, and clear with the session")
  func labelsHideCoveredGlyphs() {
    // The view holds its controller weakly: bind it (and use it below)
    // or the prompt dies mid-test and no labels ever render.
    let (textView, controller) = armedSearch("alpha beta gamma", caret: 0)
    type(textView, "/")
    type(textView, "t")
    #expect(!textView.vimSearchHiddenRanges.isEmpty)
    type(textView, "\u{1B}", keyCode: 53)
    #expect(textView.vimSearchHiddenRanges.isEmpty)
    #expect(controller.prompt == nil)
  }

  @Test("a programmatic note swap tears the whole search session down")
  func noteSwapClearsSearch() {
    let (textView, controller) = armedSearch("alpha beta gamma alpha beta", caret: 0)
    type(textView, "/")
    type(textView, "a")
    type(textView, "\r", keyCode: 36)
    #expect(textView.vimSearchCommitted == true)
    // The updateNSView note-switch order: teardown, then the swap.
    textView.endVimSearchForTextSwap()
    textView.string = "x"
    #expect(textView.vimSearchMatches.isEmpty)
    #expect(textView.vimSearchCommitted == false)
    #expect(textView.vimSearchHiddenRanges.isEmpty)
    // n after the swap reports instead of stepping stale offsets.
    type(textView, "n")
    #expect(controller.message?.kind == .error)
  }

  @Test("a note swap mid-prompt cancels the prompt with the session")
  func noteSwapCancelsOpenPrompt() {
    let (textView, controller) = armedSearch("alpha beta gamma", caret: 0)
    type(textView, "/")
    type(textView, "t")
    #expect(!textView.vimSearchHiddenRanges.isEmpty)
    textView.endVimSearchForTextSwap()
    textView.string = "x"
    #expect(controller.prompt == nil)
    #expect(textView.vimSearchHiddenRanges.isEmpty)
    #expect(textView.vimSearchMatches.isEmpty)
  }

  @Test("backspace during the prompt never fires the rendered-token revert")
  func backspaceInPromptSkipsTokenRevert() {
    let (textView, controller) = armedSearch("", caret: 0)
    // Render a token the bare-backspace revert would otherwise target
    // (menu-action insert; the coordinator's textDidChange normalize
    // step is invoked directly -- no delegate in the fixture).
    textView.insertText("@today", replacementRange: NSRange(location: 0, length: 0))
    #expect(textView.normalizeSpecialTokens())
    let rendered = textView.string
    #expect(!rendered.contains("@today"))
    type(textView, "/")
    type(textView, "\u{08}", keyCode: 51)
    // The prompt owned the backspace: closed, and the token stayed
    // rendered (no text edit happened).
    #expect(controller.prompt == nil)
    #expect(textView.string == rendered)
  }

  @Test("Ctrl-W and Ctrl-U edit the query, never the note")
  func controlChordsEditQueryNotNote() {
    let (textView, controller) = armedSearch("alpha beta gamma", caret: 0)
    type(textView, "/")
    type(textView, "b")
    type(textView, "e")
    #expect(controller.prompt?.buffer == "be")
    textView.keyDown(
      with: keyEvent(characters: "\u{17}", ignoring: "w", keyCode: 13, modifiers: .control)
    )
    #expect(controller.prompt?.buffer.isEmpty == true)
    #expect(textView.string == "alpha beta gamma")
    type(textView, "g")
    #expect(controller.prompt?.buffer == "g")
    textView.keyDown(
      with: keyEvent(characters: "\u{15}", ignoring: "u", keyCode: 32, modifiers: .control)
    )
    #expect(controller.prompt?.buffer.isEmpty == true)
    #expect(textView.string == "alpha beta gamma")
  }

  @Test("arrow keys are ignored by the query buffer")
  func arrowKeysIgnored() {
    let (textView, controller) = armedSearch("alpha beta", caret: 0)
    type(textView, "/")
    type(textView, "b")
    textView.keyDown(
      with: keyEvent(characters: "\u{F701}", ignoring: "\u{F701}", keyCode: 125)
    )
    #expect(controller.prompt?.buffer == "b")
    #expect(textView.vimSearchMatches.count == 1)
  }

  @Test("an aborted / keeps the previous committed search for n")
  func escapeKeepsPreviousCommittedSearch() {
    let (textView, controller) = armedSearch("alpha beta alpha", caret: 0)
    type(textView, "/")
    type(textView, "b")
    type(textView, "\r", keyCode: 36)
    #expect(textView.vimSearchQuery == "b")
    type(textView, "/")
    #expect(textView.vimSearchCommitted == false)
    type(textView, "\u{1B}", keyCode: 53)
    #expect(textView.vimSearchQuery == "b")
    #expect(textView.vimSearchCommitted == true)
    type(textView, "n")
    #expect(controller.searchStatus == "1/1")
  }

  @Test("a capped result set draws bands only, never labels")
  func cappedResultsHaveNoLabels() {
    let big = String(repeating: "ab ", count: VimSearchCore.matchCap + 50)
    // The controller must stay bound past the last keystroke: the view
    // holds it weakly (AGENTS.md test footgun).
    let (textView, controller) = armedSearch(big, caret: 0)
    type(textView, "/")
    type(textView, "a")
    #expect(textView.vimSearchCapped == true)
    #expect(textView.vimSearchLabelPlans.isEmpty)
    #expect(textView.vimSearchMatches.count == VimSearchCore.matchCap)
    #expect(controller.searchStatus?.contains("+") == true)
  }

  @Test("disabling vim mode clears a committed search")
  func vimDisableClearsSearch() {
    let (textView, controller) = armedSearch("alpha beta", caret: 0)
    type(textView, "/")
    type(textView, "b")
    type(textView, "\r", keyCode: 36)
    #expect(!textView.vimSearchMatches.isEmpty)
    textView.vimModeEnabled = false
    #expect(textView.vimSearchMatches.isEmpty)
    #expect(textView.vimSearchBandsVisible == false)
    #expect(controller.searchStatus == nil)
  }

  // MARK: - Capsule surface

  @Test("the capsule renders search and command prompts, nothing else")
  func capsuleGlyphRouting() {
    #expect(VimPromptCapsule.glyph(for: .search) == "bolt.fill")
    #expect(VimPromptCapsule.glyph(for: .command) == "chevron.right")
    #expect(VimPromptCapsule.glyph(for: .wordHint) == nil)
  }

  @Test("search status formats live counts, the cap, and no-matches")
  func searchStatusFormatting() {
    let controller = VimController()
    controller.setSearchStatus(current: 3, total: 12, capped: false)
    #expect(controller.searchStatus == "3/12")
    controller.setSearchStatus(current: 1, total: 500, capped: true)
    #expect(controller.searchStatus == "1/500+")
    controller.setSearchStatus(current: 0, total: 0, capped: false)
    #expect(controller.searchStatus == "no matches")
  }

  @Test("the theme pass hands the view its search dim band")
  func searchDimBandColorInstalled() {
    let (textView, _) = armedSearch("alpha", caret: 0)
    #expect(textView.editorSearchDimBandColor != nil)
  }
}
