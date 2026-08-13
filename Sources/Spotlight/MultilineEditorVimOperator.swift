import AppKit

/// The operator applicator: resolves a `VimRangeTarget` to a concrete
/// span in the live text view, then applies delete/change/yank in ONE
/// place. This is the engine's `applyOperator` counterpart -- adding an
/// operator or a text object touches one table here, not per-pair
/// special cases.
extension PlaceholderTextView {
  func applyVimOperator(_ op: VimOperator, to target: VimRangeTarget) {
    switch target {
    case .motion(let motion):
      applyOperator(op, overMotion: motion)
    case .innerWord:
      applyOperator(op, overObject: VimTextObjects.innerWord)
    case .aroundWord:
      applyOperator(op, overObject: VimTextObjects.aroundWord)
    }
  }

  /// `yy` -- linewise yank of `count` whole lines; the caret stays put.
  /// Linewise pasteboard entries always end in a newline (the paste
  /// path's linewise cue), even for the document's final line.
  func executeYankLines(_ count: Int) {
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    var range = nsString.lineRange(for: NSRange(location: selectedRange.location, length: 0))
    for _ in 1..<max(1, count) {
      let nextStart = range.location + range.length
      guard nextStart < nsString.length else { break }
      range.length += nsString.lineRange(for: NSRange(location: nextStart, length: 0)).length
    }
    yankToVimPasteboard(nsString.substring(with: range), linewise: true)
    flashYankHighlight(over: range)
  }

  private func applyOperator(_ op: VimOperator, overMotion motion: Motion) {
    // Vim's cw acts as ce when the caret sits on a non-blank: change
    // to word END, no trailing whitespace eaten. The engine is pure
    // and cannot see the text, so the swap lives here.
    var motion = motion
    if op == .change, case .wordForward(let count) = motion, caretIsOnNonBlank {
      motion = .wordEnd(count)
    }
    switch VimMotionClass.of(motion) {
    case .charwise:
      applyCharwise(op, overMotion: motion)
    case .linewise:
      applyLinewise(op, overMotion: motion)
    }
  }

  private var caretIsOnNonBlank: Bool {
    let nsString = string as NSString
    let caret = selectedRange.location
    guard caret < nsString.length else { return false }
    return VimCharClass.of(nsString.character(at: caret)) != .whitespace
  }

  private func applyCharwise(_ op: VimOperator, overMotion motion: Motion) {
    let before = selectedRange.location
    executeMotion(motion)
    let after = selectedRange.location
    let span = NSRange(location: min(before, after), length: abs(after - before))
    if op == .yank || span.length == 0 {
      // A failed motion aborts the operator (vim: the caret must not
      // move); yank restores the caret unconditionally.
      setSelectedRange(NSRange(location: op == .yank ? span.location : before, length: 0))
    }
    apply(op, over: span, linewise: false)
  }

  /// Linewise class: `dj` takes BOTH whole lines, `dG` everything from
  /// the caret's line down (vim wise-ness; the old charwise span left
  /// half of each edge line behind).
  private func applyLinewise(_ op: VimOperator, overMotion motion: Motion) {
    let nsString = string as NSString
    let before = selectedRange.location
    executeMotion(motion)
    let after = selectedRange.location
    setSelectedRange(NSRange(location: before, length: 0))
    if before == after, isVerticalMotion(motion) {
      // `dj` on the last line / `dk` on the first: the motion failed,
      // so the operator aborts (vim leaves the buffer untouched).
      return
    }
    let lower = nsString.lineRange(for: NSRange(location: min(before, after), length: 0))
    let upper = nsString.lineRange(for: NSRange(location: max(before, after), length: 0))
    let span = NSRange(
      location: lower.location,
      length: upper.location + upper.length - lower.location
    )
    apply(op, over: span, linewise: true)
  }

  private func isVerticalMotion(_ motion: Motion) -> Bool {
    if case .up = motion { return true }
    if case .down = motion { return true }
    return false
  }

  private func applyOperator(_ op: VimOperator, overObject object: (NSString, Int) -> NSRange?) {
    let nsString = string as NSString
    guard let span = object(nsString, selectedRange.location) else { return }
    apply(op, over: span, linewise: false)
  }

  /// The single application point: yank first (vim: delete and change
  /// write the register too), then mutate for delete/change.
  private func apply(_ op: VimOperator, over span: NSRange, linewise: Bool) {
    let nsString = string as NSString
    guard span.length > 0, NSMaxRange(span) <= nsString.length else { return }
    yankToVimPasteboard(nsString.substring(with: span), linewise: linewise)
    switch op {
    case .yank:
      setSelectedRange(NSRange(location: span.location, length: 0))
      flashYankHighlight(over: span)
    case .delete:
      deleteSpan(span, linewise: linewise)
    case .change:
      changeSpan(span, linewise: linewise)
    }
  }

  private func deleteSpan(_ span: NSRange, linewise: Bool) {
    var span = span
    let nsString = string as NSString
    if linewise, span.location > 0, NSMaxRange(span) >= nsString.length {
      // Deleting through the final line also takes the preceding
      // newline so no empty tail line is left (dd's rule).
      span.location -= 1
      span.length += 1
    }
    let cursorAfter = min(span.location, max(0, nsString.length - span.length))
    insertText("", replacementRange: span)
    setSelectedRange(NSRange(location: cursorAfter, length: 0))
  }

  /// Linewise change opens an empty line where the span was (vim `cj`);
  /// charwise change just removes the span. The engine has already
  /// switched to insert mode.
  private func changeSpan(_ span: NSRange, linewise: Bool) {
    if linewise {
      insertText("\n", replacementRange: span)
      setSelectedRange(NSRange(location: span.location, length: 0))
    } else {
      insertText("", replacementRange: span)
      setSelectedRange(NSRange(location: span.location, length: 0))
    }
  }

  /// One register-write door: linewise entries are newline-terminated
  /// (the paste path's linewise cue -- an explicit wise flag on a ring
  /// entry arrives with the S2 register work).
  private func yankToVimPasteboard(_ text: String, linewise: Bool) {
    guard !text.isEmpty else { return }
    let entry = linewise && !text.hasSuffix("\n") ? text + "\n" : text
    vimPasteboard.clearContents()
    vimPasteboard.setString(entry, forType: .string)
  }
}
