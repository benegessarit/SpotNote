import AppKit

/// A committed search parked while a new `/` prompt runs, restored on
/// Escape (nvim keeps the previous pattern).
struct VimSearchStash {
  let query: String
  let bandsVisible: Bool
}

/// Vim `/` flash-search -- the view-side lane. The port of David's
/// flash.nvim search integration: type `/`, matches band-highlight live
/// (no backdrop dim -- his `modes.search.highlight.backdrop = false`),
/// every near match wears a one-letter label, pressing a label jumps
/// straight there, Enter commits for `n`/`N` cycling.
///
/// Ownership: this lane is FULLY view-owned. It never reads or writes
/// the ⌘F FindController, so `applyFindHighlight` (which selects +
/// scrolls on FindController changes) cannot fight it and ⌘F behavior
/// is untouched. The typed-char policy here (charset exclusion) is a
/// DELIBERATE divergence from the s-flash lane's probe-based
/// resolution -- flash.nvim's jump and search modes differ the same
/// way; do not merge them.
extension PlaceholderTextView {
  private var searchPromptActive: Bool {
    vimController?.prompt?.kind == .search
  }

  // MARK: - Session lifecycle

  /// Called when `/` opens the prompt: remember where the caret was so
  /// Escape can go home, and park any committed search so an aborted
  /// prompt does not destroy it (nvim keeps the previous pattern).
  func beginVimSearchSession() {
    let stash =
      vimSearchCommitted && !vimSearchQuery.isEmpty
      ? VimSearchStash(query: vimSearchQuery, bandsVisible: vimSearchBandsVisible)
      : nil
    clearVimSearch()
    vimSearchStash = stash
    vimSearchOriginCaret = selectedRange.location
  }

  /// Escape: nvim restores the pre-search position and the previous
  /// committed pattern (n/N still work after an aborted `/`).
  func cancelVimSearchSession() {
    let stash = vimSearchStash
    restoreVimSearchOriginCaret()
    clearVimSearch()
    if let stash {
      restoreVimSearch(from: stash)
    } else {
      vimController?.clearSearchStatus()
    }
    needsDisplay = true
  }

  /// Put the caret back where `/` opened. incsearch may have parked it
  /// on a since-erased query's match, so every path that acts "from the
  /// cursor" (Escape restore, the empty-⏎ repeat) must go home first --
  /// vim's cursor never actually moved.
  private func restoreVimSearchOriginCaret() {
    guard let origin = vimSearchOriginCaret else { return }
    let clamped = min(origin, (string as NSString).length)
    setSelectedRange(NSRange(location: clamped, length: 0))
    scrollRangeToVisible(selectedRange)
  }

  private func restoreVimSearch(from stash: VimSearchStash) {
    vimSearchQuery = stash.query
    let result = VimSearchCore.matches(of: stash.query, in: string)
    vimSearchMatches = result.ranges
    vimSearchCapped = result.capped
    vimSearchCurrent = VimSearchCore.currentIndex(
      matches: result.ranges,
      caret: selectedRange.location
    )
    vimSearchCommitted = !result.ranges.isEmpty
    vimSearchBandsVisible = stash.bandsVisible && vimSearchCommitted
    if vimSearchBandsVisible, let controller = vimController {
      publishVimSearchStatus(controller: controller)
    } else {
      vimController?.clearSearchStatus()
    }
  }

  /// Enter: commit -- bands persist (hlsearch), labels drop, `n`/`N`
  /// cycle from here.
  func commitVimSearch(bandsVisible: Bool) {
    vimSearchCommitted = true
    vimSearchBandsVisible = bandsVisible
    vimSearchLabelPlans = []
    removeVimSearchHiddenRanges()
    vimSearchOriginCaret = nil
    vimSearchStash = nil
    needsDisplay = true
  }

  func clearVimSearch() {
    removeVimSearchHiddenRanges()
    vimSearchQuery = ""
    vimSearchMatches = []
    vimSearchCurrent = nil
    vimSearchLabelPlans = []
    vimSearchCommitted = false
    vimSearchBandsVisible = false
    vimSearchCapped = false
    vimSearchOriginCaret = nil
    vimSearchStash = nil
    needsDisplay = true
  }

  /// A programmatic note swap (`textView.string = ...`) never fires
  /// didChangeText: tear the whole session down against the OLD text --
  /// stale offsets would crash `n`, band drawing, and the hidden-range
  /// removal once the shorter note lands.
  func endVimSearchForTextSwap() {
    if searchPromptActive {
      vimController?.cancelPrompt()
    }
    clearVimSearch()
  }

  /// `:noh` -- keep the committed query (n/N re-light it, like nvim)
  /// but hide the bands and counter.
  func dismissVimSearchHighlight() {
    vimSearchBandsVisible = false
    vimController?.clearSearchStatus()
    needsDisplay = true
  }

  // MARK: - Prompt keys

  /// Routes one keystroke of the live `/` prompt. Resolution order is
  /// flash's: extend beats label, label beats dead-end extend.
  func handleSearchPromptKey(
    event: NSEvent,
    controller: VimController,
    mods: NSEvent.ModifierFlags
  ) -> Bool {
    if event.keyCode == 53 {
      controller.cancelPrompt()
      cancelVimSearchSession()
      return true
    }
    if event.keyCode == 36 || event.keyCode == 76 {
      handleSearchPromptEnter(controller: controller)
      return true
    }
    if event.keyCode == 51 {
      controller.backspacePrompt()
      if controller.prompt == nil {
        cancelVimSearchSession()
      } else {
        recomputeVimSearch(query: controller.prompt?.buffer ?? "", controller: controller)
      }
      return true
    }
    if mods.contains(.control) {
      return handleSearchPromptControlChord(event: event, controller: controller)
    }
    // The prompt owns its keys: an unrecognized ⌥/⌘ chord is swallowed,
    // never declined -- falling through reaches handleVimKey, where ⌥J
    // (mini.move) edited the note and destroyed the session mid-prompt.
    // ⌥-composed printables (non-US layouts) are dropped too, a
    // deliberate tradeoff.
    let nonShift = mods.subtracting(.shift)
    guard nonShift.isEmpty else { return true }
    guard let typed = event.characters, !typed.isEmpty else { return true }
    consumeSearchPromptCharacters(typed, controller: controller)
    return true
  }

  /// Enter, vim's `/⏎` family. A typed query with matches commits
  /// (bands persist, n/N cycle). An EMPTY query repeats the previous
  /// committed search: restore the stash and step past the caret --
  /// pre-fix this branch destroyed the stash, so `n` errored "no
  /// previous search". A query with NO matches keeps the previous
  /// pattern exactly like Escape and reports the failure; vim would
  /// also overwrite @/ with the failed pattern -- deliberately diverged
  /// so `n` keeps working on the last real search.
  private func handleSearchPromptEnter(controller: VimController) {
    let buffer = controller.prompt?.buffer ?? ""
    controller.cancelPrompt()
    if buffer.isEmpty {
      restoreVimSearchOriginCaret()
      guard let stash = vimSearchStash else {
        clearVimSearch()
        controller.clearSearchStatus()
        controller.showMessage("no previous search", kind: .error)
        return
      }
      restoreVimSearch(from: VimSearchStash(query: stash.query, bandsVisible: true))
      vimSearchOriginCaret = nil
      vimSearchStash = nil
      executeVimFindStep(1)
      return
    }
    if vimSearchMatches.isEmpty {
      cancelVimSearchSession()
      controller.showMessage("pattern not found: \(buffer)", kind: .error)
      return
    }
    commitVimSearch(bandsVisible: true)
  }

  /// Control chords edit the QUERY, never the note (the shared
  /// `promptBufferEdit` rule) -- the search kind additionally recomputes
  /// the live matches after the edit.
  private func handleSearchPromptControlChord(
    event: NSEvent,
    controller: VimController
  ) -> Bool {
    let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
    // c_CTRL-C aborts the cmdline exactly like Escape (vim parity).
    if chars == "c" {
      controller.cancelPrompt()
      cancelVimSearchSession()
      return true
    }
    if let edited = VimController.promptBufferEdit(
      controlChord: chars,
      buffer: controller.prompt?.buffer ?? ""
    ) {
      replaceSearchPrompt(with: edited, controller: controller)
    }
    return true
  }

  private func replaceSearchPrompt(with buffer: String, controller: VimController) {
    controller.replacePromptBuffer(buffer)
    recomputeVimSearch(query: buffer, controller: controller)
  }

  /// Extend-vs-label resolution for printable input. A single typed
  /// character that names a live label jumps; everything else extends
  /// the query (the surviving-keys construction keeps the sets
  /// disjoint, so this order never shadows an extension).
  private func consumeSearchPromptCharacters(_ typed: String, controller: VimController) {
    let filtered = typed.filter { ch in
      ch.unicodeScalars.allSatisfy {
        // Arrows and friends arrive as U+F700-F8FF function-key
        // codepoints, which would append invisibly to the query.
        !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 0x20
          && !(0xF700...0xF8FF).contains($0.value)
      }
    }
    guard !filtered.isEmpty else { return }
    if filtered.count == 1, let ch = filtered.first, let jump = vimSearchLabelTarget(for: ch) {
      controller.cancelPrompt()
      jumpToVimSearchMatch(jump, controller: controller)
      return
    }
    controller.appendToPrompt(filtered)
    recomputeVimSearch(query: controller.prompt?.buffer ?? "", controller: controller)
  }

  /// A typed character names a label ONLY when it cannot extend the
  /// query (the surviving-keys construction guarantees the sets are
  /// disjoint; this just resolves the lookup).
  private func vimSearchLabelTarget(for ch: Character) -> Int? {
    guard !vimSearchLabelPlans.isEmpty else { return nil }
    let folded = Character(String(ch).lowercased())
    return vimSearchLabelPlans.first { $0.label == folded }?.matchIndex
  }

  /// Label jump: his flash config -- `register = true` (n/N work from
  /// here) + `nohlsearch = true` (bands go dark until n re-lights them).
  private func jumpToVimSearchMatch(_ index: Int, controller: VimController) {
    guard vimSearchMatches.indices.contains(index) else { return }
    vimSearchCurrent = index
    moveCaretToVimSearchCurrent()
    commitVimSearch(bandsVisible: false)
    controller.clearSearchStatus()
  }

  // MARK: - Live recompute

  func recomputeVimSearch(query: String, controller: VimController) {
    removeVimSearchHiddenRanges()
    vimSearchQuery = query
    let result = VimSearchCore.matches(of: query, in: string)
    vimSearchMatches = result.ranges
    vimSearchCapped = result.capped
    let origin = vimSearchOriginCaret ?? selectedRange.location
    vimSearchCurrent = VimSearchCore.currentIndex(matches: result.ranges, caret: origin)
    if query.isEmpty {
      vimSearchLabelPlans = []
      controller.clearSearchStatus()
    } else if result.capped {
      // Beyond the cap the extension set is computed from a PARTIAL
      // match list, so a "surviving" key could still extend an unseen
      // match -- labels would break the unambiguity invariant. Bands
      // only; narrow the query to get labels back.
      vimSearchLabelPlans = []
      publishVimSearchStatus(controller: controller)
    } else {
      let keys = VimSearchCore.survivingKeys(query: query, text: string)
      vimSearchLabelPlans = VimSearchCore.labelPlan(
        matches: result.ranges,
        caret: origin,
        keys: keys
      )
      publishVimSearchStatus(controller: controller)
    }
    moveCaretToVimSearchCurrent()
    applyVimSearchHiddenRanges()
    needsDisplay = true
  }

  private func publishVimSearchStatus(controller: VimController) {
    guard let current = vimSearchCurrent else {
      controller.setSearchStatus(current: 0, total: 0, capped: false)
      return
    }
    controller.setSearchStatus(
      current: current + 1,
      total: vimSearchMatches.count,
      capped: vimSearchCapped
    )
  }

  /// incsearch: the caret rides the current match (zero-length -- never
  /// a selection) so the view scrolls with the search.
  private func moveCaretToVimSearchCurrent() {
    guard let current = vimSearchCurrent,
      vimSearchMatches.indices.contains(current)
    else { return }
    let match = vimSearchMatches[current]
    setSelectedRange(NSRange(location: match.location, length: 0))
    scrollRangeToVisible(match)
  }

  // MARK: - n / N / *

  /// Normal-mode `n`/`N`, anchored to the CARET like vim -- the cursor
  /// may have moved since the last jump, and vim searches from where it
  /// IS: forward takes the first match strictly after the caret,
  /// backward the last strictly before, wrapping. Only the sign of
  /// `delta` matters (the dispatcher passes ±1). Like nvim, stepping
  /// re-lights the bands even after `:noh` or a label jump.
  func executeVimFindStep(_ delta: Int) {
    guard vimSearchCommitted, !vimSearchMatches.isEmpty else {
      vimController?.showMessage("no previous search", kind: .error)
      return
    }
    let caret = selectedRange.location
    if delta >= 0 {
      vimSearchCurrent = vimSearchMatches.firstIndex { $0.location > caret } ?? 0
    } else {
      vimSearchCurrent =
        vimSearchMatches.lastIndex { $0.location < caret } ?? vimSearchMatches.count - 1
    }
    vimSearchBandsVisible = true
    moveCaretToVimSearchCurrent()
    if let controller = vimController { publishVimSearchStatus(controller: controller) }
    needsDisplay = true
  }

  /// `*`: search the word under the caret, landing on the NEXT
  /// occurrence. Literal matching (no word-boundary anchoring yet --
  /// a superset of vim's \<word\>).
  func executeVimSearchWordUnderCaret() {
    let nsString = string as NSString
    guard let word = vimSearchWord(at: selectedRange.location, in: nsString) else { return }
    clearVimSearch()
    vimSearchQuery = word
    let result = VimSearchCore.matches(of: word, in: string)
    vimSearchMatches = result.ranges
    vimSearchCapped = result.capped
    vimSearchCurrent = VimSearchCore.currentIndex(
      matches: result.ranges,
      caret: selectedRange.location + 1
    )
    vimSearchCommitted = true
    vimSearchBandsVisible = true
    moveCaretToVimSearchCurrent()
    if let controller = vimController { publishVimSearchStatus(controller: controller) }
    needsDisplay = true
  }

  private func vimSearchWord(at location: Int, in nsString: NSString) -> String? {
    func isWordChar(_ index: Int) -> Bool {
      guard index >= 0, index < nsString.length else { return false }
      let scalar = Unicode.Scalar(nsString.character(at: index))
      guard let scalar else { return false }
      return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }
    var start = min(location, max(0, nsString.length - 1))
    guard nsString.length > 0 else { return nil }
    // vim *: if the caret isn't on a word, scan forward to the next one.
    while start < nsString.length, !isWordChar(start) { start += 1 }
    guard start < nsString.length else { return nil }
    while isWordChar(start - 1) { start -= 1 }
    var end = start
    while isWordChar(end) { end += 1 }
    guard end > start else { return nil }
    return nsString.substring(with: NSRange(location: start, length: end - start))
  }

  // MARK: - Painting

  /// Bands under the text: every match dim, the current match in the
  /// Visual band. No document dimming (his search config sets
  /// `backdrop = false`).
  func drawVimSearchBands(in dirtyRect: NSRect) {
    guard !vimSearchMatches.isEmpty, searchPromptActive || vimSearchBandsVisible else { return }
    let dim = editorSearchDimBandColor
    let strong = editorVisualSelectionColor
    for (index, match) in vimSearchMatches.enumerated() {
      let color = index == vimSearchCurrent ? strong : dim
      guard let color else { continue }
      color.setFill()
      for rect in vimSearchEnclosingRects(forCharacterRange: match)
      where rect.intersects(dirtyRect) {
        rect.fill()
      }
    }
  }

  /// Labels after the matched text (flash's position), bare bold
  /// letters via the shared hint renderer.
  func drawVimSearchLabels(in dirtyRect: NSRect) {
    guard searchPromptActive, !vimSearchLabelPlans.isEmpty else { return }
    for plan in vimSearchLabelPlans {
      guard let location = vimSearchLabelAnchor(forMatchAt: plan.matchIndex),
        let anchor = hintAnchorRects(forCharacterAt: location)
      else { continue }
      drawHintLabel(
        String(plan.label),
        anchor: anchor,
        ink: vimSearchLabelInk,
        bold: true,
        dirtyRect: dirtyRect
      )
    }
  }

  /// Same ink as the flash-jump labels -- one label family everywhere.
  private var vimSearchLabelInk: NSColor {
    NSColor(red: 0.651, green: 0.890, blue: 0.631, alpha: 1.0)
  }

  private func vimSearchLabelAnchor(forMatchAt index: Int) -> Int? {
    guard vimSearchMatches.indices.contains(index) else { return nil }
    let nsString = string as NSString
    guard nsString.length > 0 else { return nil }
    let match = vimSearchMatches[index]
    let desired = match.location + match.length
    if desired < nsString.length { return desired }
    return min(max(0, match.location), nsString.length - 1)
  }

  private func vimSearchEnclosingRects(forCharacterRange charRange: NSRange) -> [NSRect] {
    guard let layoutManager, let textContainer else { return [] }
    let clamped = NSIntersectionRange(
      charRange,
      NSRange(location: 0, length: (string as NSString).length)
    )
    guard clamped.length > 0 else { return [] }
    let glyphRange = layoutManager.glyphRange(
      forCharacterRange: clamped,
      actualCharacterRange: nil
    )
    var rects: [NSRect] = []
    layoutManager.enumerateEnclosingRects(
      forGlyphRange: glyphRange,
      withinSelectedGlyphRange: glyphRange,
      in: textContainer
    ) { rect, _ in
      rects.append(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
    }
    return rects
  }

  // MARK: - Hidden glyphs under labels

  private func applyVimSearchHiddenRanges() {
    guard searchPromptActive, let layoutManager else { return }
    for plan in vimSearchLabelPlans {
      guard let location = vimSearchLabelAnchor(forMatchAt: plan.matchIndex) else { continue }
      let covered = hintHiddenRange(at: location, label: String(plan.label), bold: true)
      guard covered.length > 0 else { continue }
      layoutManager.addTemporaryAttributes(
        [.foregroundColor: NSColor.clear],
        forCharacterRange: covered
      )
      vimSearchHiddenRanges.append(covered)
    }
  }

  private func removeVimSearchHiddenRanges() {
    guard let layoutManager else {
      vimSearchHiddenRanges = []
      return
    }
    for range in vimSearchHiddenRanges where range.length > 0 {
      layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
    }
    vimSearchHiddenRanges = []
  }
}
