import Foundation
import Testing

@testable import Spotlight

@Suite("Daily note destination")
struct DailyNoteDestinationTests {
  @Test("resolver maps a date to the vault daily-note path")
  func resolverMapsDateToVaultPath() throws {
    let calendar = makeCalendar()
    let root = URL(fileURLWithPath: "/tmp/SpotNoteDailyTests", isDirectory: true)
    let resolver = DailyNotePathResolver(vaultRoot: root, calendar: calendar)
    let date = try makeDate(year: 2026, month: 6, day: 15, calendar: calendar)

    let url = resolver.url(for: date)

    #expect(url.path == "/tmp/SpotNoteDailyTests/Daily/2026/06-15-2026.md")
  }

  @Test("writer creates a missing daily note and appends trimmed text")
  func writerCreatesMissingDailyNoteAndAppends() async throws {
    let calendar = makeCalendar()
    let root = try makeTempDirectory()
    let writer = DailyNoteWriter(
      resolver: DailyNotePathResolver(vaultRoot: root, calendar: calendar)
    )
    let date = try makeDate(year: 2026, month: 6, day: 15, calendar: calendar)

    let url = try await writer.append("\nfirst captured thought\n", toDailyNoteFor: date)
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(
      content == """
        ---
        type: daily
        created: 2026-06-15
        ---

        # Monday, June 15, 2026

        first captured thought

        """
    )
  }

  @Test("writer preserves indentation inside captured Markdown")
  func writerPreservesIndentedMarkdown() async throws {
    let calendar = makeCalendar()
    let root = try makeTempDirectory()
    let writer = DailyNoteWriter(
      resolver: DailyNotePathResolver(vaultRoot: root, calendar: calendar)
    )
    let date = try makeDate(year: 2026, month: 6, day: 15, calendar: calendar)

    let url = try await writer.append("\n    let answer = 42\n", toDailyNoteFor: date)
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(content.contains("\n    let answer = 42\n"))
    #expect(!content.contains("\nlet answer = 42\n"))
  }

  @Test("writer preserves existing daily text and appends after a blank line")
  func writerPreservesExistingDailyText() async throws {
    let calendar = makeCalendar()
    let root = try makeTempDirectory()
    let resolver = DailyNotePathResolver(vaultRoot: root, calendar: calendar)
    let writer = DailyNoteWriter(resolver: resolver)
    let date = try makeDate(year: 2026, month: 6, day: 15, calendar: calendar)
    let url = resolver.url(for: date)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let existing = """
      ---
      type: daily
      created: 2026-06-15
      ---

      # Custom title David already had

      Existing line
      """
    try existing.write(to: url, atomically: true, encoding: .utf8)

    let appendedURL = try await writer.append("new note line", toDailyNoteFor: date)
    let content = try String(contentsOf: appendedURL, encoding: .utf8)

    #expect(appendedURL == url)
    #expect(content == existing + "\n\nnew note line\n")
  }

  @Test("blank daily-note payload is rejected")
  func blankPayloadRejected() async throws {
    let calendar = makeCalendar()
    let writer = DailyNoteWriter(
      resolver: DailyNotePathResolver(vaultRoot: try makeTempDirectory(), calendar: calendar)
    )
    let date = try makeDate(year: 2026, month: 6, day: 15, calendar: calendar)

    await #expect(throws: DailyNoteWriterError.emptyText) {
      _ = try await writer.append("  \n\n", toDailyNoteFor: date)
    }
  }

  private func makeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
  }

  private func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) throws -> Date {
    try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
  }

  private func makeTempDirectory() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let dir = root.appendingPathComponent(
      "SpotNoteDailyDestinationTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
