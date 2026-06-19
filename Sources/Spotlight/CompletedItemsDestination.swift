import Foundation

enum CompletedItemsWriterError: Error, Equatable {
  case emptyText
}

struct CompletedItemsPathResolver: Sendable {
  static let defaultURL = URL(
    fileURLWithPath: "/Users/davidbeyer/Documents/knowledge/Captures/spotnote-completed.md",
    isDirectory: false
  )

  let url: URL
  let calendar: Calendar

  init(url: URL = Self.defaultURL, calendar: Calendar = .current) {
    self.url = url
    self.calendar = calendar
  }

  func heading(for date: Date) -> String {
    "## \(dateString(for: date))"
  }

  private func dateString(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}

enum CompletedItemsPayload {
  static func entries(from markdown: String) -> [String]? {
    let parsed = ChecklistDocument.parseMarkdown(markdown)
    let entries = parsed.text
      .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !entries.isEmpty else { return nil }
    return entries
  }
}

actor CompletedItemsWriter {
  private let resolver: CompletedItemsPathResolver
  private let fileManager: FileManager

  init(resolver: CompletedItemsPathResolver = CompletedItemsPathResolver(), fileManager: FileManager = .default) {
    self.resolver = resolver
    self.fileManager = fileManager
  }

  @discardableResult
  func append(_ text: String, completedAt date: Date = Date()) throws -> URL {
    guard let entries = CompletedItemsPayload.entries(from: text) else {
      throw CompletedItemsWriterError.emptyText
    }
    try fileManager.createDirectory(
      at: resolver.url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let existing = try existingText()
    let updated = Self.appending(
      entries: entries,
      underHeading: resolver.heading(for: date),
      to: existing
    )
    try updated.write(to: resolver.url, atomically: true, encoding: .utf8)
    return resolver.url
  }

  static func appending(entries: [String], underHeading heading: String, to existing: String) -> String {
    let block = entries.map { "- [x] \($0)" }.joined(separator: "\n")
    let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "# SpotNote Completions\n\n\(heading)\n\(block)\n"
    }
    guard let headingRange = headingRange(heading, in: existing) else {
      let separator = existing.hasSuffix("\n\n") ? "" : existing.hasSuffix("\n") ? "\n" : "\n\n"
      return existing + separator + "\(heading)\n\(block)\n"
    }
    let sectionEnd = nextHeadingStart(after: headingRange.upperBound, in: existing) ?? existing.endIndex
    let prefix = existing[..<sectionEnd]
    let suffix = existing[sectionEnd...]
    let insertion = prefix.hasSuffix("\n") ? "\(block)\n" : "\n\(block)\n"
    return String(prefix) + insertion + String(suffix)
  }

  private func existingText() throws -> String {
    guard fileManager.fileExists(atPath: resolver.url.path) else { return "" }
    return try String(contentsOf: resolver.url, encoding: .utf8)
  }

  private static func headingRange(_ heading: String, in text: String) -> Range<String.Index>? {
    if text.hasPrefix(heading + "\n") || text == heading {
      return text.startIndex..<text.index(text.startIndex, offsetBy: heading.count)
    }
    return text.range(of: "\n\(heading)\n").map { text.index(after: $0.lowerBound)..<$0.upperBound }
      ?? text.range(of: "\n\(heading)").map { text.index(after: $0.lowerBound)..<$0.upperBound }
  }

  private static func nextHeadingStart(after index: String.Index, in text: String) -> String.Index? {
    text[index...].range(of: "\n## ")?.lowerBound
  }
}
