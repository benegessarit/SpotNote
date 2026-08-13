import Core
import Foundation

public enum VaultNoteState: String, CaseIterable, Codable, Identifiable, Sendable {
  case tasks

  public var id: String { rawValue }

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
    case .tasks: return ""
    }
  }

  func normalizedMarkdown(_ markdown: String) -> String {
    switch self {
    case .tasks: return Self.normalizedTasksMarkdown(markdown)
    }
  }

  private static func normalizedTasksMarkdown(_ markdown: String) -> String {
    let body = NotePayload.trimmingTrailingLineWhitespace(
      in: droppingLeadingNewlines(from: markdown)
    )
    // Normalize every recognized heading to its Title-Case canonical (so the note
    // isn't a mix of `## HABITS` / `# todo` / `## Tray`). Do not inject or reorder
    // sections: header-less notes stay header-less, and fresh inboxes open blank.
    return normalizingSectionHeadings(in: body)
  }

  private static func normalizingSectionHeadings(in markdown: String) -> String {
    markdown
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { SpotNoteSectionHeadings.canonicalHeading(for: String($0)) ?? String($0) }
      .joined(separator: "\n")
  }

  private static func droppingLeadingNewlines(from markdown: String) -> String {
    var index = markdown.startIndex
    while index < markdown.endIndex, markdown[index] == "\n" || markdown[index] == "\r" {
      index = markdown.index(after: index)
    }
    return String(markdown[index...])
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
  /// The note's mtime as of our last read or write. The vault is
  /// multi-writer (Neovim, Hermes, crons): a debounced overwrite may only
  /// land when the file still matches what this session last saw --
  /// otherwise the external edit wins the canonical path and OUR text
  /// diverts to a conflict sibling.
  private var lastKnownModification: Date?
  /// One sibling per conflict episode: later keystrokes update the same
  /// file instead of scattering a sibling per debounce tick.
  private var activeConflictURL: URL?
  private var onConflict: (@Sendable (URL) -> Void)?

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

  /// Called with the conflict sibling's URL the first time a debounced
  /// write diverts because the note changed on disk under this session.
  public func setConflictHandler(_ handler: (@Sendable (URL) -> Void)?) {
    onConflict = handler
  }

  func load() -> Chat? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let rawText = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let text = state.normalizedMarkdown(rawText)
    if text != rawText {
      try? text.write(to: url, atomically: true, encoding: .utf8)
    }
    lastKnownModification = modificationDate()
    activeConflictURL = nil
    let updatedAt = lastKnownModification ?? Date()
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
    let debounce = debounce
    let text = state.normalizedMarkdown(text)
    pendingWrite = Task {
      do { try await Task.sleep(for: debounce) } catch { return }
      persist(text)
    }
  }

  private func persist(_ text: String) {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if let target = conflictTarget() {
        try text.write(to: target, atomically: true, encoding: .utf8)
        if activeConflictURL == nil {
          activeConflictURL = target
          onConflict?(target)
        }
        return
      }
      try text.write(to: url, atomically: true, encoding: .utf8)
      lastKnownModification = modificationDate()
    } catch {
      // The editor should never crash on a vault write failure; the text
      // remains in memory and the next edit/quit flush can retry.
    }
  }

  /// Non-nil when the canonical note may not be overwritten: the file
  /// changed on disk since this session last read or wrote it (or exists
  /// but was never read). Returns the sibling URL our text goes to.
  private func conflictTarget() -> URL? {
    if let activeConflictURL { return activeConflictURL }
    guard let current = modificationDate() else { return nil }
    let drift = lastKnownModification.map { abs(current.timeIntervalSince($0)) } ?? .infinity
    if drift < 0.001 { return nil }
    let stamp = Self.conflictStampFormatter.string(from: Date())
    let base = url.deletingPathExtension().lastPathComponent
    return url.deletingLastPathComponent()
      .appending(path: "\(base).conflict-\(stamp).md", directoryHint: .notDirectory)
  }

  private static let conflictStampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  func flush() async {
    await pendingWrite?.value
    pendingWrite = nil
  }

  private func modificationDate() -> Date? {
    // NSURL caches resource values; go through FileManager for a fresh stat.
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attributes?[.modificationDate] as? Date
  }
}

typealias VaultInboxDocument = VaultNoteDocument
