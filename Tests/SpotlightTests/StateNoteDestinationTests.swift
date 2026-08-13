import Foundation
import Testing

@testable import Spotlight

@Suite("State note destination")
struct StateNoteDestinationTests {
  @Test("writer creates missing State file and appends the bullet")
  func writerCreatesMissingStateFile() async throws {
    let url = try makeTempDirectory().appending(path: "State.md", directoryHint: .notDirectory)
    let writer = StateNoteWriter(resolver: StateNotePathResolver(url: url))

    try await writer.append("- ship the thing")
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(content == "- ship the thing\n")
  }

  @Test("writer appends after existing content without adding a blank paragraph")
  func writerAppendsAfterExistingContent() async throws {
    let url = try makeTempDirectory().appending(path: "State.md", directoryHint: .notDirectory)
    try "- first item".write(to: url, atomically: true, encoding: .utf8)
    let writer = StateNoteWriter(resolver: StateNotePathResolver(url: url))

    try await writer.append("- second item")
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(content == "- first item\n- second item\n")
  }

  @Test("writer preserves an existing trailing newline (single-newline suffix)")
  func writerPreservesTrailingNewline() async throws {
    let url = try makeTempDirectory().appending(path: "State.md", directoryHint: .notDirectory)
    try "- first item\n".write(to: url, atomically: true, encoding: .utf8)
    let writer = StateNoteWriter(resolver: StateNotePathResolver(url: url))

    try await writer.append("- second item")
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(content == "- first item\n- second item\n")
  }

  @Test("writer files multiple bullet lines in one append verbatim")
  func writerFilesMultipleBulletLines() async throws {
    let url = try makeTempDirectory().appending(path: "State.md", directoryHint: .notDirectory)
    let writer = StateNoteWriter(resolver: StateNotePathResolver(url: url))

    try await writer.append("- a\n- b\n- c")
    let content = try String(contentsOf: url, encoding: .utf8)

    #expect(content == "- a\n- b\n- c\n")
  }

  @Test("blank State payload is rejected")
  func blankPayloadRejected() async throws {
    let url = try makeTempDirectory().appending(path: "State.md", directoryHint: .notDirectory)
    let writer = StateNoteWriter(resolver: StateNotePathResolver(url: url))

    await #expect(throws: StateNoteWriterError.emptyText) {
      try await writer.append("  \n\n")
    }
  }

  private func makeTempDirectory() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let dir = root.appendingPathComponent(
      "SpotNoteStateNoteDestinationTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
