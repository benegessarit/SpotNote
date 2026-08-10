import Foundation
import Testing

@testable import Core

@Suite("ChatStore persist failure surfacing")
struct ChatStorePersistFailureTests {
  /// The debounced write is the only persist path with no throwing
  /// caller; a failure there must reach the handler instead of being
  /// swallowed (teardown P0: silent data loss).
  @Test("debounced write failure reaches the handler")
  func debouncedWriteFailureReachesHandler() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(
      path: "chatstore-fail-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
      try? FileManager.default.removeItem(at: dir)
    }

    let store = try ChatStore(directory: dir, debounce: .milliseconds(5))
    let chat = try await store.create()
    let failures = FailureRecorder()
    await store.setPersistFailureHandler { id, _ in failures.record(id) }

    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
    await store.update(id: chat.id, text: "text that cannot reach disk")
    await store.flush()

    #expect(failures.ids == [chat.id])
  }

  @Test("clean debounced writes never invoke the handler")
  func cleanWritesStaySilent() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(
      path: "chatstore-ok-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = try ChatStore(directory: dir, debounce: .milliseconds(5))
    let chat = try await store.create()
    let failures = FailureRecorder()
    await store.setPersistFailureHandler { id, _ in failures.record(id) }

    await store.update(id: chat.id, text: "lands on disk")
    await store.flush()

    #expect(failures.ids.isEmpty)
    let saved = try await #require(store.get(chat.id))
    #expect(saved.text == "lands on disk")
  }

  private final class FailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [UUID] = []
    var ids: [UUID] {
      lock.lock()
      defer { lock.unlock() }
      return stored
    }
    func record(_ id: UUID) {
      lock.lock()
      defer { lock.unlock() }
      stored.append(id)
    }
  }
}
