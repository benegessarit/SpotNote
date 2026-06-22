import Foundation

/// Actor-backed chat persistence. Every edit is held in memory and
/// written to disk after a small debounce window, so keystrokes (even
/// inside a large pasted chunk) never trigger a synchronous file write.
/// Large buffers still round-trip through a single atomic write per
/// window rather than a write per character.
public actor ChatStore {
  private let directory: URL
  private let debounce: Duration
  private var chats: [UUID: Chat] = [:]
  private var pendingWrites: [UUID: Task<Void, Never>] = [:]
  /// Monotonic per-chat write token. Lets a resumed debounce task detect that
  /// a newer edit superseded it after its sleep completed, so it never clears
  /// a newer task's slot.
  private var writeGeneration: [UUID: Int] = [:]

  public init(directory: URL, debounce: Duration = .milliseconds(300)) throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    self.directory = directory
    self.debounce = debounce
  }

  /// Loads persisted chats into memory. This is intentionally explicit so
  /// app launch can construct the store cheaply and let the UI appear before
  /// any disk scan or JSON decoding work happens.
  public func loadFromDisk() {
    chats = Self.loadAll(from: directory)
  }

  /// Default on-disk location for saved chats.
  ///
  /// Uses the system Application Support location for the current process.
  /// A sandboxed build resolves this inside its container; the SwiftPM-built
  /// installed app resolves it under `~/Library/Application Support`.
  public static func defaultDirectory() throws -> URL {
    return try standardDirectory()
  }

  private static func standardDirectory() throws -> URL {
    let appSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return chatsDirectory(in: appSupport)
  }

  private static func chatsDirectory(in appSupport: URL) -> URL {
    appSupport
      .appending(path: "SpotNote", directoryHint: .isDirectory)
      .appending(path: "Chats", directoryHint: .isDirectory)
  }

  /// All chats -- pinned first, then unpinned, each group sorted by
  /// most-recently-edited.
  public func list() -> [Chat] {
    chats.values.sorted { lhs, rhs in
      if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
      return lhs.updatedAt > rhs.updatedAt
    }
  }

  public func get(_ id: UUID) -> Chat? { chats[id] }

  /// Creates a new empty chat and writes it synchronously so it exists
  /// on disk before the caller takes further action (e.g. switching the
  /// UI to it).
  public func create() throws -> Chat {
    let now = Date()
    let chat = Chat(id: UUID(), createdAt: now, updatedAt: now, text: "")
    chats[chat.id] = chat
    try persistNow(chat)
    return chat
  }

  /// Applies an edit to the in-memory chat and schedules a debounced
  /// write. Repeated calls within the debounce window collapse into one
  /// disk write at the end of the window -- this is what keeps large
  /// paste-then-edit flows cheap.
  public func update(id: UUID, text: String) {
    guard var chat = chats[id] else { return }
    chat.text = text
    chat.updatedAt = Date()
    chats[id] = chat
    scheduleWrite(id: id)
  }

  /// Re-inserts a chat that was previously removed via `delete`. Used by
  /// the session-level undo path, so the original `id`, `createdAt`, and
  /// last-edited text are preserved on restore.
  public func restore(_ chat: Chat) throws {
    chats[chat.id] = chat
    try persistNow(chat)
  }

  /// Imports chats from a portable archive. Existing chats are never
  /// overwritten; an incoming duplicate id is assigned a fresh id while
  /// preserving text, timestamps, and pin state.
  @discardableResult
  public func importChats(_ imported: [Chat]) throws -> [Chat] {
    var inserted: [Chat] = []
    for chat in imported {
      let resolved = uniqueImportedChat(from: chat)
      chats[resolved.id] = resolved
      try persistNow(resolved)
      inserted.append(resolved)
    }
    return inserted
  }

  public func togglePin(id: UUID) throws {
    guard var chat = chats[id] else { return }
    chat.isPinned.toggle()
    chats[id] = chat
    try persistNow(chat)
  }

  public func delete(id: UUID) throws {
    pendingWrites[id]?.cancel()
    pendingWrites[id] = nil
    writeGeneration[id] = nil
    chats[id] = nil
    let url = fileURL(for: id)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  /// Awaits every pending debounced write. Call before app termination
  /// or when the user triggers an explicit navigation that should
  /// observe current on-disk state.
  ///
  /// Re-snapshots after each drain: a write scheduled while we were awaiting
  /// an earlier one would be invisible to a single snapshot, so loop until no
  /// debounced writes remain in flight.
  public func flush() async {
    while !pendingWrites.isEmpty {
      let tasks = Array(pendingWrites.values)
      for task in tasks { await task.value }
    }
  }

  // MARK: - Private

  private static func loadAll(from directory: URL) -> [UUID: Chat] {
    let filenames = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    let decoder = JSONDecoder()
    var result: [UUID: Chat] = [:]
    for filename in filenames where filename.hasSuffix(".json") {
      let url = directory.appending(path: filename, directoryHint: .notDirectory)
      guard let data = try? Data(contentsOf: url),
        let chat = try? decoder.decode(Chat.self, from: data)
      else { continue }
      result[chat.id] = chat
    }
    return result
  }

  private func scheduleWrite(id: UUID) {
    pendingWrites[id]?.cancel()
    let generation = (writeGeneration[id] ?? 0) + 1
    writeGeneration[id] = generation
    let window = debounce
    pendingWrites[id] = Task { [weak self] in
      do { try await Task.sleep(for: window) } catch { return }
      await self?.performDebouncedWrite(id: id, generation: generation)
    }
  }

  private func performDebouncedWrite(id: UUID, generation: Int) {
    // A newer edit may have superseded this task after its sleep completed
    // but before it resumed. Only clear the slot if it still belongs to us,
    // so we never wipe a newer pending write that flush would then miss.
    guard writeGeneration[id] == generation else { return }
    pendingWrites[id] = nil
    guard let chat = chats[id] else { return }
    try? persistNow(chat)
  }

  private func persistNow(_ chat: Chat) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(chat)
    try data.write(to: fileURL(for: chat.id), options: .atomic)
  }

  private func uniqueImportedChat(from chat: Chat) -> Chat {
    guard chats[chat.id] != nil else { return chat }
    return Chat(
      id: UUID(),
      createdAt: chat.createdAt,
      updatedAt: chat.updatedAt,
      text: chat.text,
      isPinned: chat.isPinned
    )
  }

  private func fileURL(for id: UUID) -> URL {
    directory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
  }
}
