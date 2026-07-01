import Combine
import Core
import Foundation

/// UI-facing, main-actor-isolated view model over a `ChatStore`. Owns
/// the currently-edited chat's `id` and `text`, forwards user edits to
/// the store (which debounces disk writes internally), and publishes
/// transient `NavigationPreview` snapshots driving the HUD's feedback
/// overlay.
///
/// All chat-switching happens by assigning to `currentID` + `currentText`
/// directly -- `persistIfNeeded()` is only invoked from the SwiftUI
/// binding setter, so programmatic switches never overwrite the old
/// chat with the new chat's text.
@MainActor
final class ChatSession: ObservableObject {
  @Published var currentText: String = ""
  @Published var currentChecklistLines: [Int: ChecklistLineState] = [:]
  @Published private(set) var currentID: UUID?
  @Published private(set) var currentVaultState: VaultNoteState?
  @Published private(set) var chats: [Chat] = []

  private let store: ChatStore
  private let vaultDocuments: [VaultNoteState: VaultNoteDocument]
  private let vaultDocumentOrder: [VaultNoteState]

  init(
    store: ChatStore,
    vaultInbox: VaultInboxDocument? = nil,
    vaultDocuments: [VaultNoteDocument]? = nil
  ) {
    self.store = store
    let documents = vaultDocuments ?? vaultInbox.map { [$0] } ?? []
    self.vaultDocuments = Dictionary(uniqueKeysWithValues: documents.map { ($0.state, $0) })
    self.vaultDocumentOrder = documents.map(\.state)
  }

  /// Loads the chat list and restores the vault-backed inbox when it
  /// exists. If there is no vault inbox, restores the most-recently-edited
  /// app-local chat. If the store is empty, creates a fresh chat so the
  /// user can start typing immediately.
  func bootstrap() async {
    await store.loadFromDisk()
    chats = await availableChats()
    if currentID != nil { return }
    if !currentText.isEmpty {
      _ = await createBlankChat(initialText: currentText)
      return
    }
    if let preferredVaultState = vaultDocuments[.tasks] != nil ? VaultNoteState.tasks : vaultDocumentOrder.first {
      await switchVaultState(preferredVaultState)
      return
    }
    if let mostRecent = chats.first {
      loadCurrentChat(mostRecent)
    } else {
      _ = await createBlankChat()
    }
  }

  func reload() async {
    await flush()
    await store.loadFromDisk()
    chats = await availableChats()
    if let id = currentID, let current = chats.first(where: { $0.id == id }) {
      loadCurrentChat(current)
    } else if let mostRecent = chats.first {
      loadCurrentChat(mostRecent)
    } else {
      _ = await createBlankChat()
    }
  }

  func jump(to chat: Chat) {
    loadCurrentChat(chat)
  }

  /// Called from the SwiftUI binding setter after a user-driven edit so
  /// the store can schedule its debounced write.
  func persistIfNeeded() {
    currentChecklistLines = ChecklistDocument.prunedChecklistLines(currentChecklistLines, for: currentText)
    let visibleSnapshot = currentText
    let snapshot = serializedCurrentText()
    guard let id = currentID else {
      Task { [weak self] in
        guard let self else { return }
        await self.createCurrentChatForPendingEdit(visibleSnapshot)
      }
      return
    }
    if let vault = vaultDocument(for: id) {
      Task { await vault.update(text: snapshot) }
      return
    }
    let store = store
    Task { await store.update(id: id, text: snapshot) }
  }

  func updateChecklistLines(_ lines: [Int: ChecklistLineState]) {
    let pruned = ChecklistDocument.prunedChecklistLines(lines, for: currentText)
    guard currentChecklistLines != pruned else { return }
    currentChecklistLines = pruned
    persistIfNeeded()
  }

  func flush() async {
    await store.flush()
    for vault in vaultDocuments.values {
      await vault.flush()
    }
  }

  // MARK: - Private

  private func loadCurrentChat(_ chat: Chat) {
    let document = ChecklistDocument.parseMarkdown(chat.text)
    currentID = chat.id
    currentVaultState = vaultState(for: chat.id)
    currentText = document.text
    currentChecklistLines = document.checklistLines
  }

  private func serializedCurrentText() -> String {
    ChecklistDocument.serializeMarkdown(text: currentText, checklistLines: currentChecklistLines)
  }

  private func createBlankChat(initialText: String = "") async -> Bool {
    guard let chat = try? await store.create() else { return false }
    currentID = chat.id
    currentVaultState = nil
    let document = ChecklistDocument.parseMarkdown(initialText)
    currentText = document.text
    currentChecklistLines = document.checklistLines
    if !initialText.isEmpty {
      await store.update(id: chat.id, text: serializedCurrentText())
    }
    chats = await availableChats()
    return true
  }

  private func createCurrentChatForPendingEdit(_ snapshot: String) async {
    guard currentID == nil else {
      persistIfNeeded()
      return
    }
    guard currentText == snapshot else { return }
    _ = await createBlankChat(initialText: snapshot)
  }

}

extension ChatSession {
  func switchVaultState(_ state: VaultNoteState) async {
    guard let vault = vaultDocuments[state] else { return }
    await flush()
    let chat = await vault.load() ?? vault.emptyChat()
    loadCurrentChat(chat)
    chats = await availableChats()
  }

  private func availableChats() async -> [Chat] {
    let vaultIDs = Set(vaultDocuments.values.map(\.id))
    let saved = await store.list().filter { !vaultIDs.contains($0.id) }
    var vaultChats: [Chat] = []
    for state in vaultDocumentOrder {
      guard let vault = vaultDocuments[state], let chat = await vault.load() else { continue }
      vaultChats.append(chat)
    }
    return vaultChats + saved
  }

  private func vaultDocument(for id: UUID?) -> VaultNoteDocument? {
    guard let id else { return nil }
    return vaultDocuments.values.first { $0.id == id }
  }

  private func vaultState(for id: UUID?) -> VaultNoteState? {
    guard let id else { return nil }
    return vaultDocuments.first { $0.value.id == id }?.key
  }
}
