import Foundation
import Testing

@testable import Spotlight

@Suite("Tray note destination")
struct TrayNoteDestinationTests {
  @Test("writer creates missing tray file and appends plain text")
  func writerCreatesMissingTrayFile() async throws {
    let url = try makeTempDirectory().appending(path: "tray.md", directoryHint: .notDirectory)
    let writer = TrayNoteWriter(resolver: TrayNotePathResolver(url: url))

    try await writer.append("loose thought")
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(content == "loose thought\n")
  }

  @Test("writer appends after existing content without adding a blank paragraph")
  func writerAppendsAfterExistingContent() async throws {
    let url = try makeTempDirectory().appending(path: "tray.md", directoryHint: .notDirectory)
    try "first thought".write(to: url, atomically: true, encoding: .utf8)
    let writer = TrayNoteWriter(resolver: TrayNotePathResolver(url: url))

    try await writer.append("second thought")
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(content == "first thought\nsecond thought\n")
  }

  @Test("writer trims trailing whitespace on each captured line")
  func writerTrimsTrailingWhitespace() async throws {
    let url = try makeTempDirectory().appending(path: "tray.md", directoryHint: .notDirectory)
    let writer = TrayNoteWriter(resolver: TrayNotePathResolver(url: url))

    try await writer.append("loose thought  \n  indented detail\t")
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(content == "loose thought\n  indented detail\n")
  }

  @Test("blank tray payload is rejected")
  func blankPayloadRejected() async throws {
    let url = try makeTempDirectory().appending(path: "tray.md", directoryHint: .notDirectory)
    let writer = TrayNoteWriter(resolver: TrayNotePathResolver(url: url))

    await #expect(throws: TrayNoteWriterError.emptyText) {
      try await writer.append("  \n\n")
    }
  }

  private func makeTempDirectory() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let dir = root.appendingPathComponent("SpotNoteTrayNoteDestinationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
