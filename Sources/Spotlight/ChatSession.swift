import Combine
import Core
import Foundation

/// Transient state pushed by `ChatSession` whenever a navigation action
/// happens. The UI renders a small overlay from it and auto-clears after
/// a short delay.
struct NavigationPreview: Equatable, Sendable {
  /// Short human-readable label shown at the top of the overlay
  /// ("new note", "note 2 of 5", "only one note", "already on a blank note").
  let actionLabel: String
  /// Chats to list in the overlay. For single-message indicators this
  /// may be empty.
  let chats: [Chat]
  let currentID: UUID?
  /// Optional chat to flash with a transient accent so the user can
  /// see exactly which row a non-cycling action affected. Currently set
  /// when ⌘Z restores a previously deleted chat.
  let highlightedID: UUID?
}

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
  @Published private(set) var navigationPreview: NavigationPreview?
  /// Stack of deleted-chat snapshots pushed by `deleteCurrent` and
  /// popped by `undoDelete` (⌘Z). Supports multi-level undo -- pressing
  /// ⌘Z repeatedly restores successive deletions in reverse order.
  /// Cleared whole on the next user-driven edit or new-chat action so
  /// undo doesn't span unrelated work.
  @Published private(set) var deletedStack: [Chat] = []

  /// Convenience: the most recently deleted chat, nil when nothing is
  /// pending restore. Views (`NavigationOverlay.canUndo`) and the
  /// window controller's key monitor read this.
  var lastDeleted: Chat? { deletedStack.last }

  private let store: ChatStore
  private let vaultDocuments: [VaultNoteState: VaultNoteDocument]
  private let vaultDocumentOrder: [VaultNoteState]
  private var previewDismissTask: Task<Void, Never>?
  /// While true, `announce` skips scheduling auto-dismiss so the
  /// navigation overlay stays put. Driven by the window controller's
  /// modifier-key monitor (typically the ⌃ key for ⌃N/⌃P cycling).
  private var keepNavigationOpen = false
  private static let previewDismissDelay: Duration = .milliseconds(1400)
  private static let deletePreviewDelay: Duration = .milliseconds(4000)

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
      await switchVaultState(preferredVaultState, announcing: false)
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

  func currentChatSnapshot() -> Chat? {
    guard let id = currentID else { return nil }
    var snapshot =
      chats.first(where: { $0.id == id })
      ?? Chat(id: id, createdAt: Date(), updatedAt: Date(), text: currentText)
    snapshot.text = serializedCurrentText()
    return snapshot
  }

  /// Binds to ⌘N -- creates a fresh blank chat unconditionally (even
  /// when already on an empty one; a user may deliberately want a
  /// second blank slate).
  func newChat() async {
    deletedStack = []
    guard await createBlankChat() else { return }
    announce("new note")
  }

  /// Binds to ⌃N -- step to the next older chat, wrapping to the
  /// newest after the oldest. Never creates a chat.
  func cycleOlder() async { await cycle(by: +1) }

  /// Binds to ⌃P -- step to the next newer chat, wrapping to the
  /// oldest after the newest. Never creates a chat.
  func cycleNewer() async { await cycle(by: -1) }

  private func cycle(by delta: Int) async {
    chats = await availableChats()
    guard !chats.isEmpty else { return }
    guard chats.count > 1 else {
      announce("only one note")
      return
    }
    let index = chats.firstIndex(where: { $0.id == currentID }) ?? 0
    let count = chats.count
    let next = ((index + delta) % count + count) % count
    let chat = chats[next]
    loadCurrentChat(chat)
    announce("note \(next + 1) of \(count)")
  }

  /// Switches the editor to `chat` immediately. Used by the fuzzy
  /// palette (⌘P) to jump to any saved note. Bypasses the cycle preview
  /// since the user just made an explicit choice.
  func jump(to chat: Chat) {
    deletedStack = []
    if navigationPreview != nil {
      navigationPreview = nil
      previewDismissTask?.cancel()
      previewDismissTask = nil
    }
    loadCurrentChat(chat)
  }

  /// Binds to ⌘D -- removes the current app-local chat and lands on the
  /// next available note. The vault inbox is protected from chat-library
  /// deletion because it is a real Markdown file in the knowledge vault.
  func deleteCurrent() async {
    guard let id = currentID else { return }
    guard vaultDocument(for: id) == nil else {
      announce("vault file stays")
      return
    }
    var snapshot =
      chats.first(where: { $0.id == id })
      ?? Chat(id: id, createdAt: Date(), updatedAt: Date(), text: currentText)
    snapshot.text = serializedCurrentText()
    try? await store.delete(id: id)
    deletedStack.append(snapshot)
    chats = await availableChats()
    if let replacement = chats.first {
      loadCurrentChat(replacement)
      announce("deleted", sticky: true)
    } else {
      _ = await createBlankChat()
      announce("deleted", includingList: false, sticky: true)
    }
  }

  /// Binds to ⌘Z when `lastDeleted != nil`. Re-inserts the captured
  /// chat (preserving its original id/timestamps) and switches to it.
  /// No-op when there is nothing to restore -- the window controller's
  /// key monitor checks this and lets the editor handle text undo
  /// instead.
  func undoDelete() async {
    guard let chat = deletedStack.popLast() else { return }
    try? await store.restore(chat)
    chats = await availableChats()
    loadCurrentChat(chat)
    announce("restored", sticky: true, highlightedID: chat.id)
  }

  func togglePin() async {
    guard let id = currentID else { return }
    guard vaultDocument(for: id) == nil else {
      announce("vault file is pinned")
      return
    }
    try? await store.togglePin(id: id)
    chats = await availableChats()
    let wasPinned = chats.first(where: { $0.id == id })?.isPinned ?? false
    announce(wasPinned ? "pinned ★" : "unpinned", sticky: false)
  }

  /// Called from the SwiftUI binding setter after a user-driven edit so
  /// the store can schedule its debounced write. Also clears
  /// `lastDeleted` (so ⌘Z stops undoing a delete once the user starts
  /// editing again) and dismisses the navigation overlay immediately
  /// (the user has committed to the chat they landed on, so the
  /// browse-list shouldn't linger past the first keystroke).
  func persistIfNeeded() {
    deletedStack = []
    if navigationPreview != nil {
      navigationPreview = nil
      previewDismissTask?.cancel()
      previewDismissTask = nil
    }
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

  private func announce(
    _ label: String,
    includingList: Bool = true,
    sticky: Bool = false,
    highlightedID: UUID? = nil
  ) {
    navigationPreview = NavigationPreview(
      actionLabel: label,
      chats: includingList ? chats : [],
      currentID: currentID,
      highlightedID: highlightedID
    )
    previewDismissTask?.cancel()
    previewDismissTask = nil
    if keepNavigationOpen { return }
    let delay = sticky ? Self.deletePreviewDelay : Self.previewDismissDelay
    scheduleDismiss(after: delay)
  }

  /// Pauses or resumes the auto-dismiss timer for the navigation
  /// overlay. Called by the window controller's `flagsChanged` monitor
  /// so that as long as the cycle modifier (e.g. ⌃) is held down, the
  /// list of files stays visible regardless of the timer.
  func setNavigationHeldOpen(_ held: Bool) {
    keepNavigationOpen = held
    if held {
      previewDismissTask?.cancel()
      previewDismissTask = nil
    } else if navigationPreview != nil {
      scheduleDismiss(after: Self.previewDismissDelay)
    }
  }

  private func scheduleDismiss(after delay: Duration) {
    previewDismissTask?.cancel()
    previewDismissTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      self?.navigationPreview = nil
    }
  }
}

extension ChatSession {
  func switchVaultState(_ state: VaultNoteState, announcing: Bool = true) async {
    guard let vault = vaultDocuments[state] else { return }
    await flush()
    let chat = await vault.load() ?? vault.emptyChat()
    loadCurrentChat(chat)
    chats = await availableChats()
    if announcing { announce(state.switchLabel, includingList: false) }
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
