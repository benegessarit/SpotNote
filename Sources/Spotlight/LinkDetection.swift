import Foundation

/// One pasted http(s) URL in the note, with the display-only conceal
/// geometry the editor renders it with: `https://host/path` shows as just
/// `host` (nvim conceallevel parity), the scheme and path collapsing to
/// hairline spans unless the caret touches the link. The stored Markdown
/// string is never rewritten -- every range here indexes into it.
struct LinkSpan: Equatable {
  let range: NSRange
  let url: URL
  /// The `https://` (or `http://`) prefix -- always concealed.
  let leadingConceal: NSRange
  /// Path/query/fragment tail; length 0 when the URL is host-only.
  let trailingConceal: NSRange

  /// The host (+ port) span left visible at full size.
  var visibleRange: NSRange {
    let start = NSMaxRange(leadingConceal)
    return NSRange(location: start, length: trailingConceal.location - start)
  }
}

enum LinkDetection {
  /// http(s) URLs in `text`, in document order. Scheme-less bare domains
  /// are deliberately ignored: concealment only pays for itself on full
  /// pasted URLs, and ordinary prose ("see example.com") must never
  /// restyle while typed.
  static func spans(in text: String) -> [LinkSpan] {
    guard text.contains("://") else { return [] }
    guard
      let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
      )
    else { return [] }
    let nsText = text as NSString
    var result: [LinkSpan] = []
    detector.enumerateMatches(
      in: text,
      range: NSRange(location: 0, length: nsText.length)
    ) { match, _, _ in
      guard let match, let url = match.url,
        let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
      else { return }
      if let span = span(for: nsText.substring(with: match.range), at: match.range.location, url: url) {
        result.append(span)
      }
    }
    return result
  }

  /// The span whose range touches `location` (closed on both ends), so a
  /// caret sitting immediately before or after a link still reveals it.
  static func span(touching location: Int, in spans: [LinkSpan]) -> LinkSpan? {
    spans.first { location >= $0.range.location && location <= NSMaxRange($0.range) }
  }

  /// The span containing character `location` (half-open, hover hit-test).
  static func span(at location: Int, in spans: [LinkSpan]) -> LinkSpan? {
    spans.first { location >= $0.range.location && location < NSMaxRange($0.range) }
  }

  private static func span(for matched: String, at location: Int, url: URL) -> LinkSpan? {
    let ns = matched as NSString
    let schemeSep = ns.range(of: "://")
    // A detector match without a literal scheme (bare "example.com") has
    // no conceal geometry -- skip it entirely.
    guard schemeSep.location != NSNotFound else { return nil }
    let hostStart = NSMaxRange(schemeSep)
    let tail = ns.rangeOfCharacter(
      from: CharacterSet(charactersIn: "/?#"),
      options: [],
      range: NSRange(location: hostStart, length: ns.length - hostStart)
    )
    let hostEnd = tail.location == NSNotFound ? ns.length : tail.location
    guard hostEnd > hostStart else { return nil }
    return LinkSpan(
      range: NSRange(location: location, length: ns.length),
      url: url,
      leadingConceal: NSRange(location: location, length: hostStart),
      trailingConceal: NSRange(location: location + hostEnd, length: ns.length - hostEnd)
    )
  }
}
