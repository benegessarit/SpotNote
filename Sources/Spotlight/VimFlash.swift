import Foundation

/// Direction for native Flash-style jumps.
enum VimFlashDirection: Equatable, Sendable {
  case forward
  case backward
}

/// Search request emitted by the vim controller while Flash is active.
struct VimFlashRequest: Equatable, Sendable {
  let query: String
  let direction: VimFlashDirection
  let count: Int

  init(query: String, direction: VimFlashDirection, count: Int) {
    self.query = query
    self.direction = direction
    self.count = max(1, count)
  }
}

/// A labeled Flash destination. The location is a UTF-16 offset suitable
/// for `NSTextView.setSelectedRange(_:)`; the label is what the user types
/// after the search query to jump there.
struct VimFlashTarget: Equatable, Sendable {
  let location: Int
  let label: String
}

enum VimFlash {
  private static let lowercaseLabelAlphabet = Array("asdfghjklqwertyuiopzxcvbnm")
  private static let labelAlphabet = lowercaseLabelAlphabet + lowercaseLabelAlphabet.map { Character($0.uppercased()) }

  static func targetLocation(in text: String, from location: Int, request: VimFlashRequest) -> Int? {
    guard !request.query.isEmpty, !text.isEmpty else { return nil }
    let matches = matchingLocations(in: text, from: location, request: request)
    guard matches.count >= request.count else { return nil }
    return matches[request.count - 1]
  }

  static func targets(
    in text: String,
    from location: Int,
    request: VimFlashRequest,
    limit: Int = .max
  ) -> [VimFlashTarget] {
    let locations = matchingLocations(in: text, from: location, request: request, limit: limit)
    let labels = labels(for: locations.count)
    return zip(locations, labels).map { location, label in
      VimFlashTarget(location: location, label: label)
    }
  }

  static func lineTargets(in text: String, from _: Int, limit: Int = .max) -> [VimFlashTarget] {
    guard limit > 0 else { return [] }
    let nsString = text as NSString
    guard nsString.length > 0 else { return [] }
    var locations: [Int] = []
    var location = 0
    while location < nsString.length, locations.count < limit {
      let line = nsString.lineRange(for: NSRange(location: location, length: 0))
      locations.append(line.location)
      let next = line.location + line.length
      guard next > location else { break }
      location = next
    }
    let labels = labels(for: locations.count)
    return zip(locations, labels).map { location, label in
      VimFlashTarget(location: location, label: label)
    }
  }

  private static func matchingLocations(
    in text: String,
    from location: Int,
    request: VimFlashRequest,
    limit: Int = .max
  ) -> [Int] {
    guard !request.query.isEmpty, !text.isEmpty, limit > 0 else { return [] }
    let clampedLocation = min(max(0, location), text.utf16.count)
    let indices = request.direction == .forward ? Array(text.indices) : Array(text.indices.reversed())
    var matches: [Int] = []
    matches.reserveCapacity(min(limit, 96))
    for index in indices {
      let offset = utf16Offset(of: index, in: text)
      guard isCandidate(offset, relativeTo: clampedLocation, direction: request.direction),
        text[index...].hasPrefix(request.query)
      else { continue }
      matches.append(offset)
      if matches.count == limit { break }
    }
    return matches
  }

  private static func isCandidate(
    _ offset: Int,
    relativeTo location: Int,
    direction: VimFlashDirection
  ) -> Bool {
    switch direction {
    case .forward: return offset > location
    case .backward: return offset < location
    }
  }

  static func labels(for count: Int) -> [String] {
    guard count > 0 else { return [] }
    let alphabet = labelAlphabet.map(String.init)
    var labels = Array(alphabet.prefix(min(count, alphabet.count)))
    guard labels.count < count else { return labels }

    for first in alphabet {
      for second in alphabet {
        labels.append(first + second)
        if labels.count == count { return labels }
      }
    }
    return Array(labels.prefix(count))
  }

  private static func utf16Offset(of index: String.Index, in text: String) -> Int {
    text.utf16.distance(from: text.utf16.startIndex, to: index.samePosition(in: text.utf16) ?? text.utf16.endIndex)
  }
}
