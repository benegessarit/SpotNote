import AppKit

extension PlaceholderTextView {
  func handleFlashPromptKey(
    event: NSEvent,
    controller: VimController,
    mods: NSEvent.ModifierFlags
  ) -> Bool {
    if event.keyCode == 53 {
      controller.cancelPrompt()
      clearFlashHints()
      return true
    }
    if event.keyCode == 36 || event.keyCode == 76 {
      jumpToFlashCountTarget(controller: controller)
      return true
    }
    if event.keyCode == 51 {
      backspaceFlashPrompt(controller: controller)
      return true
    }
    let nonShift = mods.subtracting(.shift)
    guard nonShift.isEmpty else { return false }
    guard let typed = event.characters, !typed.isEmpty else { return true }
    for ch in FlashPromptInput.filtered(typed) {
      consumeFlashCharacter(String(ch), controller: controller)
    }
    return true
  }

  private func backspaceFlashPrompt(controller: VimController) {
    if !flashLabelBuffer.isEmpty {
      flashLabelBuffer.removeLast()
      needsDisplay = true
      return
    }
    controller.backspacePrompt()
    refreshFlashHints(controller: controller)
  }

  private func jumpToFlashCountTarget(controller: VimController) {
    guard let prompt = controller.prompt,
      case .flash(let direction, let count) = prompt.kind,
      !prompt.buffer.isEmpty
    else {
      controller.cancelPrompt()
      clearFlashHints()
      return
    }
    let request = VimFlashRequest(query: prompt.buffer, direction: direction, count: count)
    if performFlashJump(request) {
      controller.cancelPrompt()
      clearFlashHints()
    } else {
      controller.submitFlash(prompt.buffer)
      clearFlashHints()
    }
  }

  private func consumeFlashCharacter(_ char: String, controller: VimController) {
    guard let prompt = controller.prompt,
      case .flash = prompt.kind
    else { return }

    let labelProbe = flashLabelBuffer + char.lowercased()
    if !prompt.buffer.isEmpty, jumpIfFlashLabelMatches(labelProbe, controller: controller) {
      return
    }
    if !prompt.buffer.isEmpty, flashHints.contains(where: { $0.label.hasPrefix(labelProbe) }) {
      flashLabelBuffer = labelProbe
      needsDisplay = true
      return
    }

    controller.appendToPrompt(char)
    flashLabelBuffer = ""
    refreshFlashHints(controller: controller)
  }

  private func jumpIfFlashLabelMatches(_ label: String, controller: VimController) -> Bool {
    guard let target = flashHints.first(where: { $0.label == label }) else { return false }
    let range = NSRange(location: target.location, length: 0)
    setSelectedRange(range)
    scrollRangeToVisible(range)
    controller.cancelPrompt()
    clearFlashHints()
    return true
  }

  private func refreshFlashHints(controller: VimController) {
    guard let prompt = controller.prompt,
      case .flash(let direction, let count) = prompt.kind,
      !prompt.buffer.isEmpty
    else {
      clearFlashHints()
      return
    }
    let request = VimFlashRequest(query: prompt.buffer, direction: direction, count: count)
    flashHints = VimFlash.targets(in: string, from: selectedRange.location, request: request, limit: 96)
    needsDisplay = true
  }

  func clearFlashHints() {
    guard !flashHints.isEmpty || !flashLabelBuffer.isEmpty else { return }
    flashHints = []
    flashLabelBuffer = ""
    needsDisplay = true
  }

  func drawFlashHints(in dirtyRect: NSRect) {
    guard !flashHints.isEmpty,
      let layoutManager,
      let textContainer
    else { return }
    layoutManager.ensureLayout(for: textContainer)
    let visibleHints =
      flashLabelBuffer.isEmpty
      ? flashHints
      : flashHints.filter { $0.label.hasPrefix(flashLabelBuffer) }
    for hint in visibleHints {
      drawFlashHint(hint, dirtyRect: dirtyRect, layoutManager: layoutManager, textContainer: textContainer)
    }
  }

  private func drawFlashHint(
    _ hint: VimFlashTarget,
    dirtyRect: NSRect,
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer
  ) {
    let nsString = string as NSString
    guard hint.location >= 0,
      hint.location < nsString.length,
      layoutManager.numberOfGlyphs > 0
    else { return }
    let glyphIndex = min(
      layoutManager.glyphIndexForCharacter(at: hint.location),
      max(0, layoutManager.numberOfGlyphs - 1)
    )
    let line = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    let glyph = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
    guard !line.isEmpty, !glyph.isEmpty else { return }
    let pill = flashHintRect(label: hint.label, glyph: glyph, line: line)
    guard pill.intersects(dirtyRect) else { return }
    drawFlashHintPill(
      label: hint.label,
      in: pill,
      active: !flashLabelBuffer.isEmpty && hint.label.hasPrefix(flashLabelBuffer)
    )
  }

  private func flashHintRect(label: String, glyph: NSRect, line: NSRect) -> NSRect {
    let attrs = flashHintTextAttributes(active: true)
    let labelWidth = ceil((label as NSString).size(withAttributes: attrs).width)
    let width = max(labelWidth + 8, 16)
    let height = min(EditorMetrics.lineHeight - 3, 19)
    return NSRect(
      x: textContainerOrigin.x + glyph.minX - 3,
      y: textContainerOrigin.y + line.minY + (line.height - height) / 2,
      width: width,
      height: height
    )
  }

  private func drawFlashHintPill(label: String, in rect: NSRect, active: Bool) {
    let background =
      active
      ? NSColor(red: 0.65, green: 0.89, blue: 0.63, alpha: 0.96)
      : NSColor(red: 0.55, green: 0.69, blue: 0.98, alpha: 0.96)
    let path = NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5)
    background.setFill()
    path.fill()
    NSColor.black.withAlphaComponent(0.18).setStroke()
    path.lineWidth = 0.75
    path.stroke()

    let attrs = flashHintTextAttributes(active: active)
    let textSize = (label as NSString).size(withAttributes: attrs)
    let textRect = NSRect(
      x: rect.midX - textSize.width / 2,
      y: rect.midY - textSize.height / 2 - 0.5,
      width: textSize.width,
      height: textSize.height
    )
    (label as NSString).draw(in: textRect, withAttributes: attrs)
  }

  private func flashHintTextAttributes(active: Bool) -> [NSAttributedString.Key: Any] {
    [
      .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
      .foregroundColor: active
        ? NSColor(red: 0.09, green: 0.13, blue: 0.10, alpha: 1)
        : NSColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 1)
    ]
  }
}

private enum FlashPromptInput {
  static func filtered(_ raw: String) -> String {
    raw.filter { ch in
      ch.unicodeScalars.allSatisfy { scalar in
        !scalar.properties.isDefaultIgnorableCodePoint && scalar.value >= 0x20
      }
    }
  }
}
