import Foundation

/// The vim operator grammar: operators compose with range producers
/// (motions or text objects) in ONE place instead of per-pair special
/// cases. Target semantics are DAVID'S nvim, not stock vim -- deliberate
/// deviations (x never yanks, visual p never clobbers) live elsewhere
/// and stay.
enum VimOperator: Equatable, Sendable {
  case delete
  case change
  case yank
}

/// What an operator applies over. Motions resolve through the live text
/// view (display-line j/k need layout); text objects are pure functions
/// in `VimTextObjects`.
enum VimRangeTarget: Equatable, Sendable {
  case motion(Motion)
  case innerWord
  case aroundWord
}

/// Vim's motion wise-ness. `dj` is LINEWISE (two whole lines), `dw`
/// charwise-exclusive, `de` charwise-inclusive-by-result (AppKit's
/// word-forward already lands past the word's last character, so the
/// exclusive span covers the whole word -- the enum records vim's class
/// for readers; the applicator maps both charwise classes to the same
/// span math because our caret sits BETWEEN characters).
enum VimMotionClass: Equatable, Sendable {
  case charwise
  case linewise

  static func of(_ motion: Motion) -> VimMotionClass {
    switch motion {
    case .up, .down, .documentStart, .documentEnd:
      return .linewise
    default:
      return .charwise
    }
  }
}

/// Character classes for vim word semantics: a "word" is a run of
/// keyword characters OR a run of punctuation; whitespace separates.
/// Shared by the `w` motion scan and the word text objects.
enum VimCharClass: Equatable {
  case whitespace
  case keyword
  case punctuation

  static func of(_ codeUnit: unichar) -> VimCharClass {
    guard let scalar = UnicodeScalar(UInt32(codeUnit)) else { return .punctuation }
    if CharacterSet.whitespacesAndNewlines.contains(scalar) { return .whitespace }
    if CharacterSet.alphanumerics.contains(scalar) || scalar.value == 95 { return .keyword }
    return .punctuation
  }
}

/// Pure text-object range producers (`iw`/`aw` wave; the markdown
/// family follows the same shape). Each returns the object's range at
/// the caret, or nil when the document is empty. Pure functions over
/// (text, caret) -- unit-tested without a text view, golden-vectorable
/// against headless nvim.
enum VimTextObjects {
  /// `iw`: the run of same-class characters under the caret (keyword,
  /// punctuation, or whitespace run -- vim selects whichever the cursor
  /// is on). A caret at end-of-text grabs the run just before it.
  static func innerWord(in text: NSString, at caret: Int) -> NSRange? {
    let length = text.length
    guard length > 0 else { return nil }
    var anchor = min(max(0, caret), length - 1)
    // Never cross a line boundary: a caret sitting ON a newline
    // (end of line) belongs to the run before it, like vim's cursor
    // resting on the line's last cell.
    if text.character(at: anchor) == 0x0A, anchor > 0, text.character(at: anchor - 1) != 0x0A {
      anchor -= 1
    }
    let cls = VimCharClass.of(text.character(at: anchor))
    if cls == .whitespace, text.character(at: anchor) == 0x0A { return nil }
    var start = anchor
    while start > 0 {
      let prev = text.character(at: start - 1)
      if prev == 0x0A || VimCharClass.of(prev) != cls { break }
      start -= 1
    }
    var end = anchor + 1
    while end < length {
      let next = text.character(at: end)
      if next == 0x0A || VimCharClass.of(next) != cls { break }
      end += 1
    }
    return NSRange(location: start, length: end - start)
  }

  /// `aw`: the word plus its TRAILING whitespace run; when there is no
  /// trailing whitespace on the line, the LEADING run joins instead
  /// (vim's rule). From whitespace, vim takes the whitespace plus the
  /// following word.
  static func aroundWord(in text: NSString, at caret: Int) -> NSRange? {
    guard var range = innerWord(in: text, at: caret) else { return nil }
    let length = text.length
    let anchorClass = VimCharClass.of(text.character(at: range.location))
    if anchorClass == .whitespace {
      // whitespace anchor: extend through the following word.
      var end = range.location + range.length
      if end < length, text.character(at: end) != 0x0A {
        let cls = VimCharClass.of(text.character(at: end))
        while end < length {
          let next = text.character(at: end)
          if next == 0x0A || VimCharClass.of(next) != cls { break }
          end += 1
        }
        range.length = end - range.location
      }
      return range
    }
    var end = range.location + range.length
    var tookTrailing = false
    while end < length {
      let next = text.character(at: end)
      if next == 0x0A || VimCharClass.of(next) != .whitespace { break }
      end += 1
      tookTrailing = true
    }
    if tookTrailing {
      return NSRange(location: range.location, length: end - range.location)
    }
    var start = range.location
    while start > 0 {
      let prev = text.character(at: start - 1)
      if prev == 0x0A || VimCharClass.of(prev) != .whitespace { break }
      start -= 1
    }
    return NSRange(location: start, length: range.location + range.length - start)
  }
}
