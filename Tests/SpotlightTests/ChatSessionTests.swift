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

  @Test("bootstrap displays checklist Markdown as icon-only plain text")
  func bootstrapStripsChecklistMarkdownFromEditableText() async throws {
    let dir = try makeTempDirectory()
    let writer = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let chat = try await writer.create()
    await writer.update(
      id: chat.id,
      text: "[x] legacy checked item\nplain note\narray[x] stays code-ish"
    )
    await writer.flush()

    let reader = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let session = ChatSession(store: reader)

    await session.bootstrap()

    #expect(session.currentText == "legacy checked item\nplain note\narray[x] stays code-ish")
    #expect(session.currentChecklistLines == [0: .checked])
  }

  @Test("bootstrap prefers the vault SpotNote inbox over newer app-local notes")
  func bootstrapPrefersVaultInbox() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let newerLocal = try await store.create()
    await store.update(id: newerLocal.id, text: "[   ] ")
    await store.flush()

    let inboxURL = dir.appending(path: "spotnote-inbox.md", directoryHint: .notDirectory)
    let inboxText = "[ ] Email down @ 120\n[ ] Write pass email for Cure51"
    try inboxText.write(to: inboxURL, atomically: true, encoding: .utf8)
    let vaultInbox = VaultInboxDocument(url: inboxURL, debounce: .milliseconds(20))
    let session = ChatSession(store: store, vaultInbox: vaultInbox)

    await session.bootstrap()

    #expect(session.currentID == vaultInbox.id)
    #expect(session.currentText == "## To Do\nEmail down @ 120\nWrite pass email for Cure51")
    #expect(session.currentChecklistLines == [1: .unchecked, 2: .unchecked])
    #expect(session.chats.first?.id == vaultInbox.id)
  }

  @Test("editing the vault SpotNote inbox keeps checklist Markdown on disk")
  func vaultInboxAutosavesEdits() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let inboxURL = dir.appending(path: "spotnote-inbox.md", directoryHint: .notDirectory)
    try "[ ] old inbox\n[ x ] done item".write(to: inboxURL, atomically: true, encoding: .utf8)
    let vaultInbox = VaultInboxDocument(url: inboxURL, debounce: .milliseconds(20))
    let session = ChatSession(store: store, vaultInbox: vaultInbox)

    await session.bootstrap()
    #expect(session.currentText == "## To Do\nold inbox\ndone item")
    #expect(session.currentChecklistLines == [1: .unchecked, 2: .checked])

    session.currentText = "## To Do\nupdated inbox   \ndone item\t"
    session.persistIfNeeded()
    await session.flush()

    let saved = try String(contentsOf: inboxURL, encoding: .utf8)
    #expect(saved == "## To Do\n[   ] updated inbox\n[ x ] done item")
  }

  @Test("bootstrap ignores tray.md as a live editor note")
  func bootstrapIgnoresTrayAsLiveEditorNote() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir.appending(path: "store"), debounce: .milliseconds(20))
    let tasksURL = dir.appending(path: "spotnote-inbox.md", directoryHint: .notDirectory)
    let trayURL = dir.appending(path: "tray.md", directoryHint: .notDirectory)
    try "[   ] existing task".write(to: tasksURL, atomically: true, encoding: .utf8)
    try "random thought".write(to: trayURL, atomically: true, encoding: .utf8)
    let session = ChatSession(
      store: store,
      vaultDocuments: [
        VaultNoteDocument(state: .tasks, url: tasksURL, debounce: .milliseconds(20))
      ]
    )

    await session.bootstrap()
    #expect(session.currentVaultState == .tasks)
    #expect(session.currentText == "## To Do\nexisting task")
    #expect(session.currentChecklistLines == [1: .unchecked])
    #expect(try String(contentsOf: tasksURL, encoding: .utf8) == "## To Do\n[   ] existing task")
  }

  @Test("undo delete restores checklist state")
  func undoDeleteRestoresChecklistState() async throws {
    let dir = try makeTempDirectory()
    let writer = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let chat = try await writer.create()
    await writer.update(id: chat.id, text: "[ x ] done item")
    await writer.flush()
    let reader = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let session = ChatSession(store: reader)

    await session.bootstrap()
    #expect(session.currentText == "done item")
    #expect(session.currentChecklistLines == [0: .checked])

    await session.deleteCurrent()
    await session.undoDelete()

    #expect(session.currentText == "done item")
    #expect(session.currentChecklistLines == [0: .checked])
  }

  private func makeTempDirectory() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let dir = root.appendingPathComponent("SpotNoteChatSessionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
