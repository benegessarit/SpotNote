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
      refreshFlashTextAppearance(controller: controller)
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
    case .flash(let direction, let count, let scope):
      guard !prompt.buffer.isEmpty else {
        controller.cancelPrompt()
        clearFlashHints()
        return
      }
      let request = VimFlashRequest(query: prompt.buffer, direction: direction, count: count, scope: scope)
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
    if shouldReadFlashLabel(char, prompt: prompt), jumpIfFlashLabelMatches(labelProbe, controller: controller) {
      return
    }
    if shouldReadFlashLabel(char, prompt: prompt), flashHints.contains(where: { $0.label.hasPrefix(labelProbe) }) {
      flashLabelBuffer = labelProbe
      refreshFlashTextAppearance(controller: controller)
      needsDisplay = true
      return
    }
    if !flashLabelBuffer.isEmpty {
      flashLabelBuffer = ""
      refreshFlashTextAppearance(controller: controller)
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

  private func shouldReadFlashLabel(_ char: String, prompt: VimController.Prompt) -> Bool {
    if isLineFlashPrompt(prompt.kind) { return true }
    guard case .flash(let direction, let count, let scope) = prompt.kind,
      regularFlashLabelsAreVisible(query: prompt.buffer)
    else { return false }
    if !flashLabelBuffer.isEmpty { return true }
    let extendedQuery = prompt.buffer + char
    let request = VimFlashRequest(query: extendedQuery, direction: direction, count: count, scope: scope)
    return VimFlash.targets(in: string, from: selectedRange.location, request: request, limit: 1).isEmpty
  }

  func regularFlashLabelsAreVisible(query: String) -> Bool {
    (query as NSString).length >= 2 && !flashHints.isEmpty
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

  func enterFlashPrompt(direction: VimFlashDirection, count: Int, scope: VimFlashScope) {
    guard let controller = vimController else { return }
    controller.enterPrompt(.flash(direction, count: count, scope: scope))
    refreshFlashPromptDisplay(controller: controller)
  }

  func refreshFlashPromptDisplay(controller: VimController) {
    refreshFlashHints(controller: controller)
  }

  private func refreshFlashHints(controller: VimController) {
    guard let prompt = controller.prompt,
      isFlashPrompt(prompt.kind)
    else {
      clearFlashHints()
      return
    }
    switch prompt.kind {
    case .flash(let direction, let count, let scope):
      isShowingLineFlashHints = false
      invalidateLineFlashRuler()
      guard !prompt.buffer.isEmpty else {
        flashHints = []
        flashLabelBuffer = ""
        refreshFlashTextAppearance(controller: controller)
        needsDisplay = true
        return
      }
      let request = VimFlashRequest(query: prompt.buffer, direction: direction, count: count, scope: scope)
      flashHints = VimFlash.targets(in: string, from: selectedRange.location, request: request, limit: 96)
      refreshFlashTextAppearance(controller: controller)
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
    clearFlashTextAppearance()
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
    guard
      !flashHints.isEmpty || !flashLabelBuffer.isEmpty || isShowingLineFlashHints
        || !flashTemporaryAttributeRanges.isEmpty
    else { return }
    flashHints = []
    flashLabelBuffer = ""
    isShowingLineFlashHints = false
    clearFlashTextAppearance()
    invalidateLineFlashRuler()
    needsDisplay = true
  }

  private func invalidateLineFlashRuler() {
    enclosingScrollView?.verticalRulerView?.needsDisplay = true
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
