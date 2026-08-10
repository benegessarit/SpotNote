import AppKit

/// Editor side of the hop-style `s` word-hint jump. Unlike the flash prompt
/// (search-then-label), word hints label every visible word start the moment
/// the prompt opens; typed keys only narrow labels, never build a query.
extension PlaceholderTextView {
  /// Hint label colors from David's nvim (rose-pine): `HopNextKey` uses
  /// the `hop_red` role — love pulled 0.6 toward true red (#F75057),
  /// because bare love is PINK (the pink labels were a diagnosed
  /// regression, fixed 2026-08-10) — and `HopNextKeyAlt` is foam.
  /// Dark themes render both plain, no bold.
  static let wordHintPrimaryColor = NSColor(
    red: 0xF7 / 255,
    green: 0x50 / 255,
    blue: 0x57 / 255,
    alpha: 1
  )
  static let wordHintAlternateColor = NSColor(
    red: 0x9C / 255,
    green: 0xCF / 255,
    blue: 0xD8 / 255,
    alpha: 1
  )

  func enterWordHintPrompt() {
    guard let controller = vimController else { return }
    let locations = wordHintTargetLocations()
    guard !locations.isEmpty else { return }
    let hints = VimWordHint.hints(
      targetLocations: locations,
      cursorLocation: selectedRange.location,
      text: string
    )
    // hop `jump_on_sole_occurrence` (default true): a single candidate
    // jumps immediately without entering the labeled prompt.
    if hints.count == 1 {
      wordHintJump(to: hints[0].location)
      return
    }
    controller.enterPrompt(.wordHint)
    wordHintTargets = hints
    wordHintBuffer = ""
    refreshWordHintAppearance()
    needsDisplay = true
  }

  private func wordHintTargetLocations() -> [Int] {
    let fullRange = NSRange(location: 0, length: (string as NSString).length)
    guard let layoutManager, let textContainer else {
      return Array(VimWordHint.wordStartLocations(in: string, range: fullRange).prefix(96))
    }
    layoutManager.ensureLayout(for: textContainer)
    let containerVisibleRect = visibleRect.offsetBy(
      dx: -textContainerOrigin.x,
      dy: -textContainerOrigin.y
    )
    let glyphRange = layoutManager.glyphRange(forBoundingRect: containerVisibleRect, in: textContainer)
    let charRange =
      glyphRange.length > 0
      ? layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
      : fullRange
    return Array(VimWordHint.wordStartLocations(in: string, range: charRange).prefix(96))
  }

  func handleWordHintPromptKey(
    event: NSEvent,
    controller: VimController,
    mods: NSEvent.ModifierFlags
  ) -> Bool {
    if event.keyCode == 53 {
      cancelWordHints(controller: controller)
      return true
    }
    if event.keyCode == 51 {
      if wordHintBuffer.isEmpty {
        cancelWordHints(controller: controller)
      } else {
        wordHintBuffer.removeLast()
        refreshWordHintAppearance()
        needsDisplay = true
      }
      return true
    }
    if event.keyCode == 36 || event.keyCode == 76 {
      cancelWordHints(controller: controller)
      return true
    }
    let nonShift = mods.subtracting(.shift)
    guard nonShift.isEmpty else { return false }
    guard let typed = event.characters, !typed.isEmpty else { return true }
    for ch in typed {
      consumeWordHintKey(String(ch), controller: controller)
    }
    return true
  }

  private func consumeWordHintKey(_ char: String, controller: VimController) {
    let probe = wordHintBuffer + char
    if let target = wordHintTargets.first(where: { $0.label == probe }) {
      wordHintJump(to: target.location)
      cancelWordHints(controller: controller)
      return
    }
    if wordHintTargets.contains(where: { $0.label.hasPrefix(probe) }) {
      wordHintBuffer = probe
      refreshWordHintAppearance()
      needsDisplay = true
      return
    }
    // hop quits hinting on a key that matches no label.
    cancelWordHints(controller: controller)
  }

  private func wordHintJump(to location: Int) {
    let clamped = min(max(0, location), (string as NSString).length)
    if vimEngine?.mode == .visual, let anchor = visualAnchor {
      visualCaret = clamped
      setSelectedRange(characterwiseRange(from: anchor, to: clamped))
    } else if vimEngine?.mode == .visualLine, let anchor = visualLineAnchor {
      visualLineCaret = clamped
      setSelectedRange(linewiseRange(from: anchor, to: clamped))
    } else {
      setSelectedRange(NSRange(location: clamped, length: 0))
    }
    scrollRangeToVisible(NSRange(location: clamped, length: 0))
    needsDisplay = true
  }

  private func cancelWordHints(controller: VimController) {
    controller.cancelPrompt()
    clearWordHintState()
  }

  func clearWordHintState() {
    guard !wordHintTargets.isEmpty || !wordHintBuffer.isEmpty else { return }
    wordHintTargets = []
    wordHintBuffer = ""
    clearFlashTextAppearance()
    needsDisplay = true
  }

  /// Labels still alive under the current narrowing buffer, with the typed
  /// prefix stripped from the displayed text (hop `reduce_label`).
  func visibleWordHintLabels() -> [(target: VimFlashTarget, display: String)] {
    wordHintTargets.compactMap { target in
      guard target.label.hasPrefix(wordHintBuffer),
        target.label.count > wordHintBuffer.count
      else { return nil }
      return (target, String(target.label.dropFirst(wordHintBuffer.count)))
    }
  }

  private func refreshWordHintAppearance() {
    clearFlashTextAppearance()
    guard let layoutManager else { return }
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    // hop `dim_unmatched` (default true): the whole surface dims while
    // hints show. Labels then take over the characters their ink covers
    // (hop's `hl_mode = "replace"`): those glyphs go clear and the label
    // letters draw in their place (`drawWordHints`), so the labels read
    // as bare red letters — no pill — exactly like David's nvim. The
    // covered span is advance-measured (`hintHiddenRange`): this editor
    // is proportional, so a one-char hide let wide labels collide with
    // the next glyph.
    let fullRange = NSRange(location: 0, length: nsString.length)
    addWordHintForeground(wordHintDimmedTextColor, range: fullRange, layoutManager: layoutManager)
    for entry in visibleWordHintLabels() {
      let covered = hintHiddenRange(at: entry.target.location, label: entry.display, bold: false)
      if covered.length > 0 {
        addWordHintForeground(.clear, range: covered, layoutManager: layoutManager)
      }
    }
  }

  private func addWordHintForeground(
    _ color: NSColor,
    range: NSRange,
    layoutManager: NSLayoutManager
  ) {
    guard range.location >= 0, range.length > 0 else { return }
    layoutManager.addTemporaryAttributes([.foregroundColor: color], forCharacterRange: range)
    flashTemporaryAttributeRanges.append(range)
  }

  private var wordHintDimmedTextColor: NSColor {
    let base = editorTextAttributes[.foregroundColor] as? NSColor ?? textColor ?? .labelColor
    return base.withAlphaComponent(0.42)
  }

  func drawWordHints(in dirtyRect: NSRect) {
    guard vimController?.prompt?.kind == .wordHint,
      !wordHintTargets.isEmpty,
      let layoutManager,
      let textContainer
    else { return }
    layoutManager.ensureLayout(for: textContainer)
    let visible = visibleWordHintLabels()
    let positions = visible.map { VimWordHint.position(of: $0.target.location, in: string) }
    let alternates = VimWordHint.alternateFlags(positions: positions, labels: visible.map(\.display))
    for (index, entry) in visible.enumerated() {
      drawWordHintLabel(
        entry.display,
        at: entry.target.location,
        alternate: alternates[index],
        dirtyRect: dirtyRect
      )
    }
  }

  private func drawWordHintLabel(
    _ label: String,
    at location: Int,
    alternate: Bool,
    dirtyRect: NSRect
  ) {
    guard let anchor = hintAnchorRects(forCharacterAt: location) else { return }
    drawHintLabel(
      label,
      anchor: anchor,
      ink: alternate ? Self.wordHintAlternateColor : Self.wordHintPrimaryColor,
      bold: false,
      dirtyRect: dirtyRect
    )
  }
}
