import AppKit

extension PlaceholderTextView {
  func vimKey(for event: NSEvent, mods: NSEvent.ModifierFlags, chars: String) -> String {
    if event.keyCode == 53 { return "\u{1B}" }
    let nonShift = mods.subtracting(.shift)
    // Option chords reach the engine as nvim-style tokens (`<M-j>`) so
    // his mini.move maps can bind them; `chars` ignores the modifier, so
    // the token carries the plain letter, not the Option glyph.
    if nonShift == .option, !chars.isEmpty { return "<M-\(chars)>" }
    if !nonShift.isEmpty { return chars }
    return event.characters ?? chars
  }
}
