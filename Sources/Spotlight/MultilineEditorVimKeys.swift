import AppKit

extension PlaceholderTextView {
  func vimKey(for event: NSEvent, mods: NSEvent.ModifierFlags, chars: String) -> String {
    if event.keyCode == 53 { return "\u{1B}" }
    if !mods.subtracting(.shift).isEmpty { return chars }
    return event.characters ?? chars
  }
}
