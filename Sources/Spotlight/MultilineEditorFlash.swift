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
    guard let prompt = controller.prompt else {
      controller.cancelPrompt()
      clearFlashHints()
      return
    }
    switch prompt.kind {
    case .flash(let direction, let count):
      guard !prompt.buffer.isEmpty else {
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
    case .lineFlash(let count):
      jumpToLineFlashCountTarget(count: count, controller: controller)
    default:
      controller.cancelPrompt()
      clearFlashHints()
    }
  }

  private func jumpToLineFlashCountTarget(count: Int, controller: VimController) {
    let index = max(0, count - 1)
    guard flashHints.indices.contains(index) else {
      controller.cancelPrompt()
      clearFlashHints()
      return
    }
    jump(to: flashHints[index], controller: controller)
  }

  private func consumeFlashCharacter(_ char: String, controller: VimController) {
    guard let prompt = controller.prompt,
      isFlashPrompt(prompt.kind)
    else { return }

    let labelProbe = flashLabelBuffer + char
    let acceptsLabelInput = isLineFlashPrompt(prompt.kind) || !prompt.buffer.isEmpty
    if acceptsLabelInput, jumpIfFlashLabelMatches(labelProbe, controller: controller) {
      return
    }
    if acceptsLabelInput, flashHints.contains(where: { $0.label.hasPrefix(labelProbe) }) {
      flashLabelBuffer = labelProbe
      needsDisplay = true
      return
    }

    guard !isLineFlashPrompt(prompt.kind) else { return }

    controller.appendToPrompt(char)
    flashLabelBuffer = ""
    refreshFlashHints(controller: controller)
  }

  private func isFlashPrompt(_ kind: VimController.PromptKind) -> Bool {
    switch kind {
    case .flash, .lineFlash:
      return true
    default:
      return false
    }
  }

  private func isLineFlashPrompt(_ kind: VimController.PromptKind) -> Bool {
    if case .lineFlash = kind { return true }
    return false
  }

  private func jumpIfFlashLabelMatches(_ label: String, controller: VimController) -> Bool {
    guard let target = flashHints.first(where: { $0.label == label }) else { return false }
    jump(to: target, controller: controller)
    return true
  }

  private func jump(to target: VimFlashTarget, controller: VimController) {
    let range = NSRange(location: target.location, length: 0)
    setSelectedRange(range)
    scrollRangeToVisible(range)
    controller.cancelPrompt()
    clearFlashHints()
  }

  private func refreshFlashHints(controller: VimController) {
    guard let prompt = controller.prompt,
      isFlashPrompt(prompt.kind)
    else {
      clearFlashHints()
      return
    }
    switch prompt.kind {
    case .flash(let direction, let count):
      guard !prompt.buffer.isEmpty else {
        clearFlashHints()
        return
      }
      let request = VimFlashRequest(query: prompt.buffer, direction: direction, count: count)
      isShowingLineFlashHints = false
      flashHints = VimFlash.targets(in: string, from: selectedRange.location, request: request, limit: 96)
      invalidateLineFlashRuler()
    case .lineFlash:
      refreshLineFlashHints()
      return
    default:
      clearFlashHints()
      return
    }
    needsDisplay = true
  }

  func refreshLineFlashHints() {
    flashHints = visibleLineFlashTargets(limit: 96)
    flashLabelBuffer = ""
    isShowingLineFlashHints = true
    invalidateLineFlashRuler()
    needsDisplay = true
  }

  func visibleLineFlashTargets(limit: Int = 96) -> [VimFlashTarget] {
    guard limit > 0,
      let layoutManager,
      let textContainer
    else { return VimFlash.lineTargets(in: string, from: selectedRange.location, limit: limit) }
    layoutManager.ensureLayout(for: textContainer)
    let nsString = string as NSString
    guard nsString.length > 0, layoutManager.numberOfGlyphs > 0 else { return [] }

    var locations: [Int] = []
    locations.reserveCapacity(min(limit, 96))
    let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
    layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragment, _, _, glyphs, stop in
      if fragment.origin.y >= self.visibleRect.maxY {
        stop.pointee = true
        return
      }
      guard fragment.maxY > self.visibleRect.minY else { return }
      let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
      locations.append(chars.location)
      if locations.count == limit { stop.pointee = true }
    }
    appendVisibleExtraLineFragmentLocation(to: &locations, limit: limit, layoutManager: layoutManager)
    let labels = VimFlash.labels(for: locations.count)
    return zip(locations, labels).map { location, label in
      VimFlashTarget(location: location, label: label)
    }
  }

  private func appendVisibleExtraLineFragmentLocation(
    to locations: inout [Int],
    limit: Int,
    layoutManager: NSLayoutManager
  ) {
    guard locations.count < limit,
      (string as NSString).hasSuffix("\n")
    else { return }
    let extra = layoutManager.extraLineFragmentRect
    guard !extra.isEmpty,
      extra.maxY > visibleRect.minY,
      extra.origin.y < visibleRect.maxY
    else { return }
    locations.append((string as NSString).length)
  }

  func clearFlashHints() {
    guard !flashHints.isEmpty || !flashLabelBuffer.isEmpty || isShowingLineFlashHints else { return }
    flashHints = []
    flashLabelBuffer = ""
    isShowingLineFlashHints = false
    invalidateLineFlashRuler()
    needsDisplay = true
  }

  private func invalidateLineFlashRuler() {
    enclosingScrollView?.verticalRulerView?.needsDisplay = true
  }

  func drawFlashHints(in dirtyRect: NSRect) {
    guard !isShowingLineFlashHints || enclosingScrollView?.verticalRulerView == nil else { return }
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
    let rect = flashHintRect(label: hint.label, glyph: glyph, line: line)
    guard rect.intersects(dirtyRect) else { return }
    drawFlashHintLabel(
      label: hint.label,
      in: rect,
      active: !flashLabelBuffer.isEmpty && hint.label.hasPrefix(flashLabelBuffer)
    )
  }

  private func flashHintRect(label: String, glyph: NSRect, line: NSRect) -> NSRect {
    let attrs = flashHintTextAttributes(active: true)
    let labelWidth = ceil((label as NSString).size(withAttributes: attrs).width)
    let height = EditorMetrics.lineHeight
    return NSRect(
      x: textContainerOrigin.x + glyph.minX,
      y: textContainerOrigin.y + line.minY,
      width: max(labelWidth + 2, glyph.width),
      height: height
    )
  }

  private func drawFlashHintLabel(label: String, in rect: NSRect, active: Bool) {
    let attrs = flashHintTextAttributes(active: active)
    let effectiveFont =
      attrs[.font] as? NSFont ?? font
      ?? .monospacedSystemFont(
        ofSize: EditorMetrics.fontSize,
        weight: .bold
      )
    let baseline = LineNumberRuler.synthesizedBaseline(fragmentHeight: rect.height, font: effectiveFont)
    let point = NSPoint(x: rect.minX, y: rect.minY + baseline - effectiveFont.ascender)
    (label as NSString).draw(at: point, withAttributes: attrs)
  }

  private func flashHintTextAttributes(active: Bool) -> [NSAttributedString.Key: Any] {
    let baseFont = font ?? NSFont.monospacedSystemFont(ofSize: EditorMetrics.fontSize, weight: .bold)
    let labelFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
      .withSize(baseFont.pointSize)
    return [
      .font: labelFont,
      .foregroundColor: active
        ? NSColor(red: 0.980, green: 0.702, blue: 0.529, alpha: 1.0)
        : NSColor(red: 0.651, green: 0.890, blue: 0.631, alpha: 1.0)
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
