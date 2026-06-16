import Core
import Foundation

/// Primary human-readable SpotNote inbox stored in David's knowledge vault.
///
/// The old HUD was backed by `spotnote-inbox.md`, not by an app-private JSON
/// scratch note. Keep that file as the default launch buffer so SpotNote stays
/// visible/editable from Neovim, Hermes, and the vault.
public actor VaultInboxDocument {
  public nonisolated static let defaultID =
    UUID(
      uuidString: "A14B9457-5E86-48F7-A7B8-33E9CC1C25B4"
    ) ?? UUID()

  public nonisolated let id: UUID
  public nonisolated let url: URL

  private let debounce: Duration
  private var pendingWrite: Task<Void, Never>?

  public init(
    url: URL = VaultInboxDocument.defaultURL(),
    id: UUID = VaultInboxDocument.defaultID,
    debounce: Duration = .milliseconds(300)
  ) {
    self.url = url
    self.id = id
    self.debounce = debounce
  }

  public static func defaultURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Documents", directoryHint: .isDirectory)
      .appending(path: "knowledge", directoryHint: .isDirectory)
      .appending(path: "Captures", directoryHint: .isDirectory)
      .appending(path: "spotnote-inbox.md", directoryHint: .notDirectory)
  }

  func load() -> Chat? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let updatedAt = modificationDate() ?? Date()
    return Chat(
      id: id,
      createdAt: updatedAt,
      updatedAt: updatedAt,
      text: text,
      isPinned: true
    )
  }

  func update(text: String) {
    pendingWrite?.cancel()
    let url = url
    let debounce = debounce
    pendingWrite = Task {
      do { try await Task.sleep(for: debounce) } catch { return }
      do {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
      } catch {
        // The editor should never crash on a vault write failure; the text
        // remains in memory and the next edit/quit flush can retry.
      }
    }
  }

  func flush() async {
    await pendingWrite?.value
    pendingWrite = nil
  }

  private func modificationDate() -> Date? {
    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
      return nil
    }
    return values.contentModificationDate
  }
}
