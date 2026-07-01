// swiftlint:disable function_body_length large_tuple
import Combine
import Foundation

/// Tiny shared text-editing helpers used by the find bar and fuzzy
/// palette. Their search fields are SwiftUI `TextField`s, which don't
/// expose cursor position or word-deletion commands the way an
/// `NSTextView` does -- so ⌃W operates on the trailing word of the
/// current query string. That's good enough because the cursor in a
/// short search field practically always sits at the end.
enum SearchTextEditing {
  static func deleteWordBackward(_ value: String) -> String {
    var trimmed = value
    while let last = trimmed.last, last.isWhitespace { trimmed.removeLast() }
    while let last = trimmed.last, !last.isWhitespace { trimmed.removeLast() }
    return trimmed
  }
}

/// State for the inline find-in-current-note bar (⌘F).
@MainActor
final class FindController: ObservableObject {
  @Published private(set) var isVisible: Bool = false
  @Published var query: String = ""
  @Published private(set) var matches: [NSRange] = []
  @Published private(set) var currentIndex: Int = 0

  init() {}

  var currentMatch: NSRange? {
    guard !matches.isEmpty, matches.indices.contains(currentIndex) else { return nil }
    return matches[currentIndex]
  }

  func open() {
    isVisible = true
  }

  func close() {
    isVisible = false
    query = ""
    matches = []
    currentIndex = 0
  }

  func toggle(text: String) {
    if isVisible {
      close()
    } else {
      open()
      if !query.isEmpty { search(in: text) }
    }
  }

  func search(in text: String) {
    if query.isEmpty {
      matches = []
      currentIndex = 0
      return
    }
    let nsText = text as NSString
    var found: [NSRange] = []
    var location = 0
    while location < nsText.length {
      let remaining = NSRange(location: location, length: nsText.length - location)
      let range = nsText.range(of: query, options: [.caseInsensitive], range: remaining)
      if range.location == NSNotFound { break }
      found.append(range)
      location = range.location + max(1, range.length)
    }
    matches = found
    currentIndex = found.isEmpty ? 0 : min(currentIndex, found.count - 1)
  }

  func next() {
    guard !matches.isEmpty else { return }
    currentIndex = (currentIndex + 1) % matches.count
  }

  func previous() {
    guard !matches.isEmpty else { return }
    currentIndex = (currentIndex - 1 + matches.count) % matches.count
  }
}
