import AppKit
import Testing

@testable import Spotlight

/// Display-line `j`/`k` behavior: motion follows wrapped visual rows, not whole
/// logical lines. Lives alongside the logical-line motion suite as an extension so
/// each test file stays within its length budget.
@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  @Test("j walks a wrapped line row-by-row instead of skipping it whole")
  func downStepsThroughWrappedDisplayRows() {
    // One logical line long enough to wrap into multiple visual rows at panelWidth,
    // followed by a short line. Display-line j must land *inside* the wrapped line
    // (on its 2nd row), not jump straight to "next".
    let wrapped = String(repeating: "wrapped bullet text ", count: 9).trimmingCharacters(
      in: .whitespaces
    )
    let textView = makeVimMotionTextView(text: "\(wrapped)\nnext")
    let wrappedLength = (wrapped as NSString).length
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.executeMotion(.down(1))
    let afterDown = textView.selectedRange.location
    #expect(afterDown > 0)  // it moved
    #expect(afterDown < wrappedLength)  // still inside the wrapped logical line, not on "next"

    textView.executeMotion(.up(1))
    #expect(textView.selectedRange.location == 0)  // k returns to the first row
  }

  @Test("k climbs a real note (hanging-indent wraps, header, blank line) without stalling")
  func upClimbsRealNoteWithoutStalling() {
    // Faithful to the live editor: a header with a surrounding blank line (post-\f)
    // and bullets, some long enough to soft-wrap, WITH hanging indent on continuation
    // rows. The regression froze `k` on the bottom bullet because the row directly
    // above was a hanging-indented wrapped continuation: right-edge affinity spilled
    // the landing index onto the next visual row, which resolved back to the start
    // row, so the step reported "didn't advance" and the caret never moved.
    let lines = [
      "## Todo",
      "",
      "- Command to have a clean organization of note including definitions and headers",
      "- Activated voice agent",
      "- Hermes claude worktree thing that is also fairly long so it wraps onto another row too",
      "- Build a cmux sidebar"
    ]
    let text = lines.joined(separator: "\n")
    let textView = makeVimMotionTextView(text: text)
    applyHangingIndentToBullets(textView)
    textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

    var previous = textView.selectedRange.location
    for _ in 0..<40 {
      textView.executeMotion(.up(1))
      let now = textView.selectedRange.location
      if textView.caretDisplayRowTop(at: now) == 0 { break }  // reached the first display row
      #expect(now < previous)  // strictly climbing — never frozen on a row mid-note
      previous = now
    }
    // Reached the first display row (the header) rather than stalling on a lower bullet.
    #expect(textView.caretDisplayRowTop(at: textView.selectedRange.location) == 0)
  }

  /// Mimic the live editor's per-line paragraph styling: bullets get a hanging
  /// indent so wrapped continuation rows align under the text, not the marker.
  private func applyHangingIndentToBullets(_ textView: PlaceholderTextView) {
    guard let storage = textView.textStorage else { return }
    let ns = textView.string as NSString
    let font = textView.font ?? .systemFont(ofSize: EditorMetrics.fontSize)
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = EditorMetrics.lineHeight
    style.maximumLineHeight = EditorMetrics.lineHeight
    style.headIndent = ceil(("  " as NSString).size(withAttributes: [.font: font]).width)
    var loc = 0
    while loc < ns.length {
      let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
      if ns.substring(with: lineRange).hasPrefix("- ") {
        storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
      }
      loc = lineRange.location + lineRange.length
    }
  }
}
