import Foundation
import Testing

@testable import Core

@Suite("ChatStore flush durability")
struct ChatStoreFlushTests {
  @Test("flush awaits the pending debounced write so the last edit is durable without sleeping")
  func flushIsDurableForLastEdit() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(50))
    let chat = try await store.create()
    await store.update(id: chat.id, text: "one")
    await store.update(id: chat.id, text: "two")
    // No sleep: flush itself must await the in-flight debounce task. A
    // single-snapshot flush, or a write slot clobbered by a superseded task,
    // would lose "two".
    await store.flush()

    let url = dir.appending(path: "\(chat.id.uuidString).json", directoryHint: .notDirectory)
    let loaded = try JSONDecoder().decode(Chat.self, from: Data(contentsOf: url))
    #expect(loaded.text == "two")
  }

  private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-flush-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
