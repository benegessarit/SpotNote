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

  @Test("togglePin persists the pin, resorts pinned-first, and survives reload")
  func togglePinPersistsAndResortsPinnedFirst() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let older = try await store.create()
    await store.update(id: older.id, text: "older note")
    try await Task.sleep(for: .milliseconds(5))
    let newer = try await store.create()
    await store.update(id: newer.id, text: "newer note")
    let session = ChatSession(store: store)
    await session.bootstrap()

    let target = try #require(session.chats.first { $0.id == older.id })
    await session.togglePin(target)

    #expect(session.chats.first?.id == older.id)
    #expect(session.chats.first?.isPinned == true)
    await store.flush()
    let reloaded = try ChatStore(directory: dir, debounce: .milliseconds(20))
    await reloaded.loadFromDisk()
    let reloadedList = await reloaded.list()
    #expect(reloadedList.first?.id == older.id)
    #expect(reloadedList.first?.isPinned == true)

    let pinned = try #require(session.chats.first { $0.id == older.id })
    await session.togglePin(pinned)
    #expect(session.chats.first?.id == newer.id)
    #expect(session.chats.allSatisfy { !$0.isPinned })
  }

  @Test("go back / go forward walk note history; new navigation clears forward")
  func goBackForwardWalkHistory() async throws {
    let store = try ChatStore(directory: makeTempDirectory(), debounce: .milliseconds(20))
    let session = ChatSession(store: store)
    await session.bootstrap()
    let first = try #require(session.currentID)

    await session.newNote()
    let second = try #require(session.currentID)
    #expect(session.canGoBack)
    #expect(!session.canGoForward)

    await session.goBack()
    #expect(session.currentID == first)
    #expect(session.canGoForward)

    await session.goForward()
    #expect(session.currentID == second)
    #expect(!session.canGoForward)

    await session.goBack()
    #expect(session.currentID == first)
    await session.newNote()
    #expect(!session.canGoForward, "fresh navigation clears the forward stack")
    await session.goBack()
    #expect(session.currentID == first)
  }

  @Test("duplicate opens a new note carrying the current text")
  func duplicateCopiesCurrentNote() async throws {
    let store = try ChatStore(directory: makeTempDirectory(), debounce: .milliseconds(20))
    let session = ChatSession(store: store)
    await session.bootstrap()
    session.currentText = "keep me"
    session.persistIfNeeded()
    let original = try #require(session.currentID)

    await session.duplicateCurrent()

    #expect(session.currentID != original)
    #expect(session.currentText == "keep me")
    #expect(session.canGoBack)
    await session.goBack()
    #expect(session.currentID == original)
    #expect(session.currentText == "keep me")
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

  @Test("bootstrap prefers the vault SpotNote inbox over newer app-local notes without adding default sections")
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
    #expect(session.currentText == "Email down @ 120\nWrite pass email for Cure51")
    #expect(session.currentChecklistLines == [0: .unchecked, 1: .unchecked])
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
    #expect(session.currentText == "old inbox\ndone item")
    #expect(session.currentChecklistLines == [0: .unchecked, 1: .checked])

    session.currentText = "updated inbox   \ndone item\t"
    session.persistIfNeeded()
    await session.flush()

    let saved = try String(contentsOf: inboxURL, encoding: .utf8)
    #expect(saved == "[   ] updated inbox\n[ x ] done item")
  }

  @Test("bootstrap normalizes a TODO heading to Title-Case Todo without inserting default sections")
  func bootstrapNormalizesTodoHeadingCase() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let inboxURL = dir.appending(path: "spotnote-inbox.md", directoryHint: .notDirectory)
    try "## TODO\n[ ] old inbox".write(to: inboxURL, atomically: true, encoding: .utf8)
    let vaultInbox = VaultInboxDocument(url: inboxURL, debounce: .milliseconds(20))
    let session = ChatSession(store: store, vaultInbox: vaultInbox)

    await session.bootstrap()

    #expect(session.currentText == "## Todo\nold inbox")
    #expect(session.currentChecklistLines == [1: .unchecked])
    #expect(try String(contentsOf: inboxURL, encoding: .utf8) == "## Todo\n[ ] old inbox")
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
    #expect(session.currentText == "existing task")
    #expect(session.currentChecklistLines == [0: .unchecked])
    #expect(try String(contentsOf: tasksURL, encoding: .utf8) == "[   ] existing task")
  }

  @Test("missing vault inbox opens blank instead of inserting a default section")
  func missingVaultInboxOpensBlankWithoutDefaultHeading() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir.appending(path: "store"), debounce: .milliseconds(20))
    let tasksURL = dir.appending(path: "spotnote-inbox.md", directoryHint: .notDirectory)
    let session = ChatSession(
      store: store,
      vaultDocuments: [
        VaultNoteDocument(state: .tasks, url: tasksURL, debounce: .milliseconds(20))
      ]
    )

    await session.bootstrap()

    #expect(session.currentVaultState == .tasks)
    #expect(session.currentText.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: tasksURL.path))
  }

  private func makeTempDirectory() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let dir = root.appendingPathComponent("SpotNoteChatSessionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
