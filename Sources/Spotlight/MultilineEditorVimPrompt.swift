import AppKit

/// Prompt-key routing: one keystroke of any open vim prompt (`:`, `/`,
/// flash, word-hint) dispatches through here from `keyDown`.
extension PlaceholderTextView {
  /// Routes one keystroke into the active prompt. Returns `true` when
  /// the event was consumed.
  func handlePromptKey(
    event: NSEvent,
    controller: VimController,
    mods: NSEvent.ModifierFlags
  ) -> Bool {
    switch controller.prompt?.kind {
    case .flash, .lineFlash:
      return handleFlashPromptKey(event: event, controller: controller, mods: mods)
    case .wordHint:
      return handleWordHintPromptKey(event: event, controller: controller, mods: mods)
    case .search:
      return handleSearchPromptKey(event: event, controller: controller, mods: mods)
    default:
      return handleCommandPromptKey(event: event, controller: controller, mods: mods)
    }
  }

  /// The `:` command prompt: Escape cancels, Enter submits, backspace
  /// shrinks, control chords edit the buffer (the shared
  /// `promptBufferEdit` rule -- never the note), printable input
  /// appends.
  private func handleCommandPromptKey(
    event: NSEvent,
    controller: VimController,
    mods: NSEvent.ModifierFlags
  ) -> Bool {
    if event.keyCode == 53 {
      controller.cancelPrompt()
      needsDisplay = true
      return true
    }
    if event.keyCode == 36 || event.keyCode == 76 {
      controller.submitPrompt()
      needsDisplay = true
      return true
    }
    if event.keyCode == 51 {
      controller.backspacePrompt()
      return true
    }
    if mods.contains(.control) {
      let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
      if let edited = VimController.promptBufferEdit(
        controlChord: chars,
        buffer: controller.prompt?.buffer ?? ""
      ) {
        controller.replacePromptBuffer(edited)
      }
      return true
    }
    let nonShift = mods.subtracting(.shift)
    guard nonShift.isEmpty else { return false }
    guard let typed = event.characters, !typed.isEmpty else { return true }
    let filtered = Self.filterPromptInput(typed)
    guard !filtered.isEmpty else { return true }
    controller.appendToPrompt(filtered)
    return true
  }

  private static func filterPromptInput(_ raw: String) -> String {
    raw.filter { ch in
      ch.unicodeScalars.allSatisfy { scalar in
        // Arrows and friends arrive as U+F700-F8FF function-key
        // codepoints, which would append invisibly to the buffer.
        !scalar.properties.isDefaultIgnorableCodePoint && scalar.value >= 0x20
          && !(0xF700...0xF8FF).contains(scalar.value)
      }
    }
  }
}
