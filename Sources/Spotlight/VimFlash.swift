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
    guard !request.query.isEmpty, !text.isEmpty else { return nil }
    let clampedLocation = min(max(0, location), text.utf16.count)
    switch request.direction {
    case .forward:
      return target(in: text, from: clampedLocation, request: request) { $0 > $1 }
    case .backward:
      return target(in: text, from: clampedLocation, request: request) { $0 < $1 }
    }
  }

  private static func target(
    in text: String,
    from location: Int,
    request: VimFlashRequest,
    isCandidate: (Int, Int) -> Bool
  ) -> Int? {
    var remaining = request.count
    let indices = request.direction == .forward ? Array(text.indices) : Array(text.indices.reversed())
    for index in indices {
      let offset = utf16Offset(of: index, in: text)
      guard isCandidate(offset, location), text[index...].hasPrefix(request.query) else { continue }
      remaining -= 1
      if remaining == 0 { return offset }
    }
    return nil
  }

  private static func utf16Offset(of index: String.Index, in text: String) -> Int {
    text.utf16.distance(from: text.utf16.startIndex, to: index.samePosition(in: text.utf16) ?? text.utf16.endIndex)
  }
}
