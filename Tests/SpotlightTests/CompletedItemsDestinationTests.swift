import Foundation
import Testing

@testable import Spotlight

@Suite("Completed items destination")
struct CompletedItemsDestinationTests {
  @Test("writer creates missing completed-items file with dated section")
  func writerCreatesMissingCompletedFile() async throws {
    let calendar = makeCalendar()
    let url = try makeTempDirectory().appending(path: "spotnote-completed.md", directoryHint: .notDirectory)
    let writer = CompletedItemsWriter(
      resolver: CompletedItemsPathResolver(url: url, calendar: calendar)
    )
    let date = try makeDate(year: 2026, month: 6, day: 17, calendar: calendar)

    try await writer.append("Email Foxglove", completedAt: date)
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(
      content == """
        # SpotNote Completions

        ## 2026-06-17
        - [x] Email Foxglove

        """
    )
  }

  @Test("writer appends under an existing date heading")
  func writerAppendsUnderExistingDateHeading() async throws {
    let calendar = makeCalendar()
    let url = try makeTempDirectory().appending(path: "spotnote-completed.md", directoryHint: .notDirectory)
    let existing = """
      # SpotNote Completions

      ## 2026-06-17
      - [x] Email Foxglove
      """
    try existing.write(to: url, atomically: true, encoding: .utf8)
    let writer = CompletedItemsWriter(
      resolver: CompletedItemsPathResolver(url: url, calendar: calendar)
    )
    let date = try makeDate(year: 2026, month: 6, day: 17, calendar: calendar)

    try await writer.append("Book Sebastian dinner", completedAt: date)
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(
      content == existing + "\n- [x] Book Sebastian dinner\n"
    )
  }

  @Test("writer preserves later sections when appending to an earlier date")
  func writerPreservesLaterSectionsWhenAppendingToEarlierDate() async throws {
    let calendar = makeCalendar()
    let url = try makeTempDirectory().appending(path: "spotnote-completed.md", directoryHint: .notDirectory)
    let existing = """
      # SpotNote Completions

      ## 2026-06-16
      - [x] Email Foxglove

      ## 2026-06-17
      - [x] Book Sebastian dinner
      """
    try existing.write(to: url, atomically: true, encoding: .utf8)
    let writer = CompletedItemsWriter(
      resolver: CompletedItemsPathResolver(url: url, calendar: calendar)
    )
    let date = try makeDate(year: 2026, month: 6, day: 16, calendar: calendar)

    try await writer.append("Approve quote", completedAt: date)
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(
      content == """
        # SpotNote Completions

        ## 2026-06-16
        - [x] Email Foxglove
        - [x] Approve quote

        ## 2026-06-17
        - [x] Book Sebastian dinner
        """
    )
  }

  @Test("writer strips existing checklist markers and preserves priority text")
  func writerStripsChecklistAndPreservesPriority() async throws {
    let calendar = makeCalendar()
    let url = try makeTempDirectory().appending(path: "spotnote-completed.md", directoryHint: .notDirectory)
    let writer = CompletedItemsWriter(
      resolver: CompletedItemsPathResolver(url: url, calendar: calendar)
    )
    let date = try makeDate(year: 2026, month: 6, day: 17, calendar: calendar)

    try await writer.append("[ x ] ! Approve quote", completedAt: date)
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(content.contains("- [x] ! Approve quote\n"))
    #expect(!content.contains("[ x ] !"))
  }

  @Test("blank completed payload is rejected")
  func blankPayloadRejected() async throws {
    let calendar = makeCalendar()
    let url = try makeTempDirectory().appending(path: "spotnote-completed.md", directoryHint: .notDirectory)
    let writer = CompletedItemsWriter(
      resolver: CompletedItemsPathResolver(url: url, calendar: calendar)
    )
    let date = try makeDate(year: 2026, month: 6, day: 17, calendar: calendar)

    await #expect(throws: CompletedItemsWriterError.emptyText) {
      try await writer.append("  \n\n", completedAt: date)
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
      "SpotNoteCompletedItemsDestinationTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
