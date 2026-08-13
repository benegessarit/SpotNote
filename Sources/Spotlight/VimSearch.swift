import Foundation

/// Pure core of vim `/` flash-search -- the port of David's flash.nvim
/// search integration (`modes.search.enabled = true`: labels on every
/// match, press a label to jump straight to that result). No AppKit;
/// every rule here is exact-testable.
///
/// The load-bearing invariant is UNAMBIGUITY: a typed key either
/// extends the query or names a label, never both. Every occurrence of
/// `query + c` starts at an occurrence of `query` -- but the DRAWN
/// match list comes from a non-overlapping scan, which skips
/// self-overlapping occurrences ("aaas" + "aa" records only (0,2), not
/// (1,2)). The extension set therefore runs its own OVERLAPPING scan of
/// the text; labels are drawn from the charset MINUS that set.
struct VimSearchLabelPlan: Equatable {
  let label: Character
  let matchIndex: Int
}

enum VimSearchCore {
  /// Live-search ceiling: a one-letter query on a huge note stops
  /// scanning here ("500+" in the capsule) so no keystroke can wedge.
  static let matchCap = 500
  /// His flash.nvim charset (flash.lua `labels`), in his order.
  static let labelKeys: [Character] = Array("asdfghjklqwertyuiopzxcvbnm")

  /// Literal, case-insensitive (the FindController semantics), capped.
  static func matches(of query: String, in text: String) -> (ranges: [NSRange], capped: Bool) {
    guard !query.isEmpty else { return ([], false) }
    let nsText = text as NSString
    var found: [NSRange] = []
    var location = 0
    while location < nsText.length {
      let remaining = NSRange(location: location, length: nsText.length - location)
      let range = nsText.range(of: query, options: [.caseInsensitive], range: remaining)
      if range.location == NSNotFound { break }
      if found.count == matchCap { return (found, true) }
      found.append(range)
      location = range.location + max(1, range.length)
    }
    return (found, false)
  }

  /// vim forward semantics: the first match at/after the caret, wrapping
  /// to the top when none follows. Nil only when there are no matches.
  static func currentIndex(matches: [NSRange], caret: Int) -> Int? {
    guard !matches.isEmpty else { return nil }
    return matches.firstIndex { $0.location >= caret } ?? 0
  }

  /// Characters that would extend the query to a non-empty match set:
  /// the (case-folded) character immediately after EVERY occurrence of
  /// the query, via an overlapping scan -- an occurrence the drawn
  /// match list skips can still be extended, and a label handed out for
  /// its next character would shadow that extension.
  static func extensionCharacters(of query: String, in text: String) -> Set<Character> {
    guard !query.isEmpty else { return [] }
    let nsText = text as NSString
    var set: Set<Character> = []
    var location = 0
    while location < nsText.length {
      let remaining = NSRange(location: location, length: nsText.length - location)
      let range = nsText.range(of: query, options: [.caseInsensitive], range: remaining)
      if range.location == NSNotFound { break }
      let next = range.location + range.length
      if next < nsText.length {
        let charRange = nsText.rangeOfComposedCharacterSequence(at: next)
        for ch in nsText.substring(with: charRange).lowercased() {
          set.insert(ch)
        }
      }
      location = range.location + 1
    }
    return set
  }

  /// The label alphabet for this round: his charset minus every
  /// extending character. Can be empty (all keys extend) -- then no
  /// labels show and every key extends, the honest fallback.
  static func survivingKeys(query: String, text: String) -> [Character] {
    let extending = extensionCharacters(of: query, in: text)
    return labelKeys.filter { !extending.contains($0) }
  }

  /// One single-character label per match, nearest the caret first,
  /// capped at the surviving alphabet -- NEVER multi-character labels
  /// (the trie's prefix-free overflow would retire single letters; far
  /// matches go band-only instead, flash.nvim's own behavior).
  static func labelPlan(
    matches: [NSRange],
    caret: Int,
    keys: [Character]
  ) -> [VimSearchLabelPlan] {
    guard !keys.isEmpty, !matches.isEmpty else { return [] }
    let byDistance = matches.indices.sorted {
      abs(matches[$0].location - caret) < abs(matches[$1].location - caret)
    }
    return zip(byDistance.prefix(keys.count), keys).map { index, key in
      VimSearchLabelPlan(label: key, matchIndex: index)
    }
  }
}
