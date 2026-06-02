import Foundation

enum VimFlashDirection: Equatable, Sendable {
  case forward
  case backward
}

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

enum VimFlash {
  static func targetLocation(in text: String, from location: Int, request: VimFlashRequest) -> Int? {
    guard !request.query.isEmpty else { return nil }
    let nsString = text as NSString
    guard nsString.length > 0 else { return nil }
    let clampedLocation = min(max(0, location), nsString.length)
    switch request.direction {
    case .forward:
      return forwardTarget(in: nsString, from: clampedLocation, request: request)
    case .backward:
      return backwardTarget(in: nsString, from: clampedLocation, request: request)
    }
  }

  private static func forwardTarget(
    in text: NSString,
    from location: Int,
    request: VimFlashRequest
  ) -> Int? {
    var remaining = request.count
    var searchStart = min(location + 1, text.length)
    while searchStart < text.length {
      let range = NSRange(location: searchStart, length: text.length - searchStart)
      let match = text.range(of: request.query, options: [], range: range)
      guard match.location != NSNotFound else { return nil }
      remaining -= 1
      if remaining == 0 { return match.location }
      searchStart = match.location + max(1, match.length)
    }
    return nil
  }

  private static func backwardTarget(
    in text: NSString,
    from location: Int,
    request: VimFlashRequest
  ) -> Int? {
    var remaining = request.count
    var searchEnd = min(location, text.length)
    while searchEnd > 0 {
      let range = NSRange(location: 0, length: searchEnd)
      let match = text.range(of: request.query, options: .backwards, range: range)
      guard match.location != NSNotFound else { return nil }
      remaining -= 1
      if remaining == 0 { return match.location }
      searchEnd = match.location
    }
    return nil
  }
}
