import AppKit

extension PlaceholderTextView {
  func handleVimInsertModeReturnKey(_ event: NSEvent) -> Bool {
    guard event.keyCode == 36 || event.keyCode == 76 else { return false }
    insertNewline(nil)
    return true
  }
}
