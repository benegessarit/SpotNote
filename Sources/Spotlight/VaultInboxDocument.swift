import Core
import Foundation

public enum VaultNoteState: String, CaseIterable, Codable, Identifiable, Sendable {
  case tasks

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .tasks: return "Tasks"
    }
  }

  public var switchLabel: String {
    switch self {
    case .tasks: return "\(displayName) 󰄱"
    }
  }

  public var defaultID: UUID {
    switch self {
    case .tasks:
      UUID(uuidString: "A14B9457-5E86-48F7-A7B8-33E9CC1C25B4") ?? UUID()
    }
  }

  public func defaultURL() -> URL {
    let captures = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Documents", directoryHint: .isDirectory)
      .appending(path: "knowledge", directoryHint: .isDirectory)
      .appending(path: "Captures", directoryHint: .isDirectory)
    switch self {
    case .tasks:
      return captures.appending(path: "spotnote-inbox.md", directoryHint: .notDirectory)
    }
  }

  var defaultMarkdown: String {
    switch self {
    case .tasks: return "## To Do\n"
    }
  }

  func normalizedMarkdown(_ markdown: String) -> String {
    switch self {
    case .tasks: return Self.normalizedTasksMarkdown(markdown)
    }
  }

  private static func normalizedTasksMarkdown(_ markdown: String) -> String {
    let body = droppingLeadingNewlines(from: markdown)
    if startsWithMarkdownHeading(body, "## To Do") { return body }
    guard !body.isEmpty else { return "## To Do\n" }
    return "## To Do\n" + body
  }

  private static func droppingLeadingNewlines(from markdown: String) -> String {
    var index = markdown.startIndex
    while index < markdown.endIndex, markdown[index] == "\n" || markdown[index] == "\r" {
      index = markdown.index(after: index)
    }
    return String(markdown[index...])
  }

  private static func startsWithMarkdownHeading(_ markdown: String, _ heading: String) -> Bool {
    let firstLine = markdown.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
      .localizedCaseInsensitiveCompare(heading) == .orderedSame
  }
}

/// Human-readable SpotNote note stored in David's knowledge vault.
///
/// The editable text stays plain inside the HUD. Checklist Markdown is
/// parsed/serialized only at this file boundary so the vault remains readable
/// from Neovim, Hermes, and ordinary Markdown tools.
public actor VaultNoteDocument {
  public nonisolated let state: VaultNoteState
  public nonisolated let id: UUID
  public nonisolated let url: URL

  private let debounce: Duration
  private var pendingWrite: Task<Void, Never>?

  public init(
    state: VaultNoteState = .tasks,
    url: URL? = nil,
    id: UUID? = nil,
    debounce: Duration = .milliseconds(300)
  ) {
    self.state = state
    self.url = url ?? state.defaultURL()
    self.id = id ?? state.defaultID
    self.debounce = debounce
  }

  func load() -> Chat? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let rawText = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let text = state.normalizedMarkdown(rawText)
    if text != rawText {
      try? text.write(to: url, atomically: true, encoding: .utf8)
    }
    let updatedAt = modificationDate() ?? Date()
    return Chat(
      id: id,
      createdAt: updatedAt,
      updatedAt: updatedAt,
      text: text,
      isPinned: true
    )
  }

  nonisolated func emptyChat(now: Date = Date()) -> Chat {
    Chat(id: id, createdAt: now, updatedAt: now, text: state.defaultMarkdown, isPinned: true)
  }

  func update(text: String) {
    pendingWrite?.cancel()
    let url = url
    let debounce = debounce
    let text = state.normalizedMarkdown(text)
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

typealias VaultInboxDocument = VaultNoteDocument
