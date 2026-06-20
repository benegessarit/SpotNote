import Foundation

extension NSString {
  /// The index marking the end of `range`'s visible content, with any trailing
  /// newline characters (`\n` / `\r`) excluded. Never returns less than
  /// `range.location`.
  ///
  /// This is the single home for the "walk back over trailing newlines" idiom
  /// that the editor, vim motions, flash labels, and the code styler all need;
  /// each derives its own shape (length, range, substring, emptiness) from it.
  func lineContentEnd(of range: NSRange) -> Int {
    var end = range.location + range.length
    while end > range.location {
      let ch = character(at: end - 1)
      guard ch == 0x0A || ch == 0x0D else { break }
      end -= 1
    }
    return end
  }
}
