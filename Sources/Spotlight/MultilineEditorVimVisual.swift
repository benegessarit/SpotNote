import AppKit

extension PlaceholderTextView {
  func executeVisualVimAction(_ action: VimAction) -> Bool {
    switch action {
    case .enterVisual:
      enterVisualMode()
    case .extendVisual(let motion):
      extendVisual(by: motion)
    case .yankVisualSelection:
      yankVisualSelection()
    case .deleteVisualSelection:
      deleteVisualSelection(switchingToInsert: false)
    case .changeVisualSelection:
      deleteVisualSelection(switchingToInsert: true)
    case .swapVisualEnds:
      swapVisualEnds()
    case .pasteOverVisualSelection:
      pasteOverVisualSelection()
    case .reselectLastVisual:
      reselectLastVisual()
    default:
      return false
    }
    return true
  }

  /// Remember the active visual range for `gv`. Called by every exit
  /// path (and the coherence repair) BEFORE the anchors are cleared.
  func captureLastVisualRange() {
    if let anchor = visualAnchor, let caret = visualCaret {
      lastVisualRange = VisualRangeMemo(anchor: anchor, caret: caret, linewise: false)
    } else if let anchor = visualLineAnchor, let caret = visualLineCaret {
      lastVisualRange = VisualRangeMemo(anchor: anchor, caret: caret, linewise: true)
    }
  }

  /// Visual `o` -- the moving end and the anchor trade places (vim), so
  /// the next motion grows the OTHER side of the selection.
  private func swapVisualEnds() {
    if let anchor = visualAnchor, let caret = visualCaret {
      visualAnchor = caret
      visualCaret = anchor
      setSelectedRange(characterwiseRange(from: caret, to: anchor))
      scrollRangeToVisible(NSRange(location: anchor, length: 0))
    } else if let anchor = visualLineAnchor, let caret = visualLineCaret {
      visualLineAnchor = caret
      visualLineCaret = anchor
      setSelectedRange(linewiseRange(from: caret, to: anchor))
      scrollRangeToVisible(NSRange(location: anchor, length: 0))
    }
    needsDisplay = true
  }

  /// Visual `p` -- replace the selection with the register WITHOUT
  /// writing the deleted text back (David's nvim maps visual p to
  /// `"_dP`; stock vim's clobber is the thing he turned off).
  private func pasteOverVisualSelection() {
    captureLastVisualRange()
    let range = selectedRange
    let pasted = vimPasteboard.string(forType: .string) ?? ""
    if range.length > 0 || !pasted.isEmpty, shouldChangeText(in: range, replacementString: pasted) {
      replaceCharacters(in: range, with: pasted)
      didChangeText()
    }
    visualAnchor = nil
    visualCaret = nil
    visualLineAnchor = nil
    visualLineCaret = nil
    let caret = min(range.location + (pasted as NSString).length, (string as NSString).length)
    setSelectedRange(NSRange(location: caret, length: 0))
    notifyVimModeChanged()
    needsDisplay = true
  }

  /// Normal `gv` -- re-enter the last visual range (same wise, same
  /// endpoints, clamped to the current text).
  private func reselectLastVisual() {
    guard let last = lastVisualRange, let engine = vimEngine else { return }
    let length = (string as NSString).length
    let anchor = min(max(0, last.anchor), length)
    let caret = min(max(0, last.caret), length)
    engine.enterVisualMode(linewise: last.linewise)
    if last.linewise {
      visualLineAnchor = anchor
      visualLineCaret = caret
      setSelectedRange(linewiseRange(from: anchor, to: caret))
    } else {
      visualAnchor = anchor
      visualCaret = caret
      setSelectedRange(characterwiseRange(from: anchor, to: caret))
    }
    scrollRangeToVisible(NSRange(location: caret, length: 0))
    notifyVimModeChanged()
    needsDisplay = true
  }

  private func enterVisualMode() {
    let length = (string as NSString).length
    let anchor = min(visualLineAnchor ?? selectedRange.location, length)
    let caret = min(visualLineCaret ?? anchor, length)
    visualLineAnchor = nil
    visualLineCaret = nil
    visualAnchor = anchor
    visualCaret = caret
    setSelectedRange(characterwiseRange(from: anchor, to: caret))
    notifyVimModeChanged()
    needsDisplay = true
  }

  private func extendVisual(by motion: Motion) {
    guard let anchor = visualAnchor else { return }
    let nsString = string as NSString
    let length = nsString.length
    let caretBefore = min(visualCaret ?? anchor, length)

    setSelectedRange(NSRange(location: caretBefore, length: 0))
    executeMotion(motion)
    let rawCaretAfter = min(selectedRange.location, length)
    let caretAfter = visualCaretLocation(
      rawCaretAfter,
      movedFrom: caretBefore,
      for: motion,
      in: nsString
    )
    visualCaret = caretAfter
    setSelectedRange(characterwiseRange(from: anchor, to: caretAfter))
    scrollRangeToVisible(NSRange(location: caretAfter, length: 0))
    needsDisplay = true
  }

  func characterwiseRange(from anchor: Int, to caret: Int) -> NSRange {
    let length = (string as NSString).length
    guard length > 0 else { return NSRange(location: 0, length: 0) }
    let clampedAnchor = min(max(0, anchor), length)
    let clampedCaret = min(max(0, caret), length)
    if clampedAnchor == length, clampedCaret == length {
      return NSRange(location: length, length: 0)
    }
    let start = min(clampedAnchor, clampedCaret)
    let end = min(max(clampedAnchor, clampedCaret) + 1, length)
    return NSRange(location: start, length: max(0, end - start))
  }

  /// Motions that land the caret PAST their target character pull back
  /// one cell in visual mode, so the selection covers exactly what vim
  /// covers: `$` stops on the line's last character, and `e` stops ON
  /// the word's last character (AppKit's word-forward lands after it --
  /// `ve` selecting the trailing space was the visible deviation).
  private func visualCaretLocation(
    _ location: Int,
    movedFrom caretBefore: Int,
    for motion: Motion,
    in nsString: NSString
  ) -> Int {
    switch motion {
    case .lineEnd:
      guard nsString.length > 0 else { return 0 }
      let probe = min(location, max(0, nsString.length - 1))
      let line = nsString.lineRange(for: NSRange(location: probe, length: 0))
      let contentEnd = nsString.lineContentEnd(of: line)
      return contentEnd > line.location ? contentEnd - 1 : line.location
    case .wordEnd:
      return location > caretBefore ? location - 1 : location
    default:
      return location
    }
  }

  private func yankVisualSelection() {
    captureLastVisualRange()
    let nsString = string as NSString
    let range = selectedRange
    if range.length > 0, range.location + range.length <= nsString.length {
      let text = nsString.substring(with: range)
      vimPasteboard.clearContents()
      vimPasteboard.setString(text, forType: .string)
    }
    exitVisualSelection(restoreCaretTo: visualCaret ?? range.location)
  }

  private func deleteVisualSelection(switchingToInsert: Bool) {
    captureLastVisualRange()
    let range = selectedRange
    let restorePoint = range.location
    if range.length > 0, shouldChangeText(in: range, replacementString: "") {
      replaceCharacters(in: range, with: "")
      didChangeText()
    }
    visualAnchor = nil
    visualCaret = nil
    setSelectedRange(NSRange(location: min(restorePoint, (string as NSString).length), length: 0))
    notifyVimModeChanged()
    _ = switchingToInsert
    needsDisplay = true
  }

  private func exitVisualSelection(restoreCaretTo location: Int) {
    visualAnchor = nil
    visualCaret = nil
    let clamped = min(location, (string as NSString).length)
    setSelectedRange(NSRange(location: clamped, length: 0))
    notifyVimModeChanged()
    needsDisplay = true
  }

  // MARK: - nvim-style visual block cursor

  /// The block cursor cell at the visual moving end. nvim keeps a block
  /// cursor visible in visual mode (over the selection); NSTextView
  /// hides the insertion point while a selection is active, so the view
  /// draws this rect itself in `draw(_:)`.
  func visualBlockCursorRect() -> NSRect? {
    guard let engine = vimEngine, engine.mode == .visual || engine.mode == .visualLine,
      let caret = visualCaret ?? visualLineCaret,
      let layoutManager, let textContainer
    else { return nil }
    let nsString = string as NSString
    guard nsString.length > 0 else { return nil }
    let clamped = min(max(0, caret), nsString.length - 1)
    let glyph = layoutManager.glyphIndexForCharacter(at: clamped)
    var rect = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: glyph, length: 1),
      in: textContainer
    )
    rect.origin.x += textContainerOrigin.x
    rect.origin.y += textContainerOrigin.y
    if rect.width < 2 {
      // Newline / zero-width cell: give the block the normal-mode width
      // so the cursor stays visible at line ends.
      rect.size.width = EditorMetrics.normalModeCursorWidth
    }
    return shrinkInsertionPointRectToFont(rect)
  }

  func drawVisualBlockCursor(in dirtyRect: NSRect) {
    guard let rect = visualBlockCursorRect(), rect.intersects(dirtyRect) else { return }
    (editorCursorColor ?? Self.normalModeCursorColor).withAlphaComponent(0.82).setFill()
    rect.fill()
  }
}
