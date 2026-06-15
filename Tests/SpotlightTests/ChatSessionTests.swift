import Core
import Foundation
import Testing

@testable import Spotlight

@MainActor
@Suite("ChatSession")
struct ChatSessionTests {
  @Test("editing before bootstrap creates and preserves the typed draft")
  func editingBeforeBootstrapCreatesAndPreservesTypedDraft() async throws {
    let store = try ChatStore(directory: makeTempDirectory(), debounce: .milliseconds(20))
    let session = ChatSession(store: store)

    session.currentText = "typed before bootstrap"
    session.persistIfNeeded()
    await session.bootstrap()
    await store.flush()

    let chats = await store.list()
    #expect(session.currentText == "typed before bootstrap")
    #expect(session.currentID != nil)
    #expect(chats.count == 1)
    #expect(chats.first?.text == "typed before bootstrap")
  }

  @Test("bootstrap displays legacy compact checked markers with spaced x")
  func bootstrapNormalizesLegacyCheckedMarkerDisplay() async throws {
    let dir = try makeTempDirectory()
    let writer = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let chat = try await writer.create()
    await writer.update(id: chat.id, text: "[x] legacy checked item\narray[x] stays code-ish")
    await writer.flush()

    let reader = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let session = ChatSession(store: reader)

    await session.bootstrap()

    #expect(session.currentText == "[ x ] legacy checked item\narray[x] stays code-ish")
  }

  private func makeTempDirectory() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let dir = root.appendingPathComponent("SpotNoteChatSessionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
