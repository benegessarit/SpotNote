import Foundation

enum DailyNoteWriterError: Error, Equatable {
  case emptyText
}

struct DailyNotePathResolver: Sendable {
  static let defaultVaultRoot = URL(
    fileURLWithPath: "/Users/davidbeyer/Documents/knowledge",
    isDirectory: true
  )

  let vaultRoot: URL
  let calendar: Calendar

  init(vaultRoot: URL = Self.defaultVaultRoot, calendar: Calendar = .current) {
    self.vaultRoot = vaultRoot
    self.calendar = calendar
  }

  func url(for date: Date) -> URL {
    let year = calendar.component(.year, from: date)
    return
      vaultRoot
      .appendingPathComponent("Daily", isDirectory: true)
      .appendingPathComponent(String(year), isDirectory: true)
      .appendingPathComponent(dateString(for: date, format: "MM-dd-yyyy") + ".md", isDirectory: false)
  }

  func frontmatterDate(for date: Date) -> String {
    dateString(for: date, format: "yyyy-MM-dd")
  }

  func titleDate(for date: Date) -> String {
    dateString(for: date, format: "EEEE, MMMM d, yyyy")
  }

  private func dateString(for date: Date, format: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = format
    return formatter.string(from: date)
  }
}

enum DailyNotePayload {
  static func normalized(_ text: String) -> String? {
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    guard let first = lines.firstIndex(where: { !isBlankLine($0) }),
      let last = lines.lastIndex(where: { !isBlankLine($0) })
    else { return nil }
    return lines[first...last].joined(separator: "\n")
  }

  private static func isBlankLine(_ line: Substring) -> Bool {
    line.allSatisfy { $0 == " " || $0 == "\t" }
  }
}

actor DailyNoteWriter {
  private let resolver: DailyNotePathResolver
  private let fileManager: FileManager

  init(resolver: DailyNotePathResolver = DailyNotePathResolver(), fileManager: FileManager = .default) {
    self.resolver = resolver
    self.fileManager = fileManager
  }

  func ensureDailyNote(for date: Date = Date()) throws -> URL {
    let url = resolver.url(for: date)
    if fileManager.fileExists(atPath: url.path) { return url }
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let initialContent = """
      ---
      type: daily
      created: \(resolver.frontmatterDate(for: date))
      ---

      # \(resolver.titleDate(for: date))

      """
    try initialContent.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  @discardableResult
  func append(_ text: String, toDailyNoteFor date: Date = Date()) throws -> URL {
    guard let payload = DailyNotePayload.normalized(text) else {
      throw DailyNoteWriterError.emptyText
    }
    let url = try ensureDailyNote(for: date)
    let existing = try String(contentsOf: url, encoding: .utf8)
    let suffix = appendSuffix(existingText: existing, payload: payload)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(suffix.utf8))
    return url
  }

  private func appendSuffix(existingText: String, payload: String) -> String {
    if existingText.isEmpty { return payload + "\n" }
    if existingText.hasSuffix("\n\n") { return payload + "\n" }
    if existingText.hasSuffix("\n") { return "\n" + payload + "\n" }
    return "\n\n" + payload + "\n"
  }
}
