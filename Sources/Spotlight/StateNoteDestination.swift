import Foundation

enum StateNoteWriterError: Error, Equatable {
  case emptyText
}

struct StateNotePathResolver: Sendable {
  static let defaultURL = URL(
    fileURLWithPath: "/Users/davidbeyer/Documents/knowledge/Work/hermes-build/Notes/State.md",
    isDirectory: false
  )

  let url: URL

  init(url: URL = Self.defaultURL) {
    self.url = url
  }
}

enum StateNotePayload {
  /// The payload arrives already shaped by the editor as one `- ` line per bullet
  /// block (`- a` / `- a\n- b`). `NotePayload.normalized` only trims blank edges and
  /// trailing whitespace and rejoins existing lines with `\n` — it does NOT re-split
  /// or re-flatten, so the per-block flatten done in the editor is preserved.
  static func normalized(_ text: String) -> String? {
    NotePayload.normalized(text)
  }
}

actor StateNoteWriter {
  private let resolver: StateNotePathResolver
  private let fileManager: FileManager

  init(resolver: StateNotePathResolver = StateNotePathResolver(), fileManager: FileManager = .default) {
    self.resolver = resolver
    self.fileManager = fileManager
  }

  @discardableResult
  func append(_ text: String) throws -> URL {
    guard let payload = StateNotePayload.normalized(text) else {
      throw StateNoteWriterError.emptyText
    }
    try fileManager.createDirectory(
      at: resolver.url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let existing = try existingText()
    let suffix = appendSuffix(existingText: existing, payload: payload)
    let handle = try FileHandle(forWritingTo: resolver.url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(suffix.utf8))
    return resolver.url
  }

  private func existingText() throws -> String {
    guard fileManager.fileExists(atPath: resolver.url.path) else {
      try "".write(to: resolver.url, atomically: true, encoding: .utf8)
      return ""
    }
    return try String(contentsOf: resolver.url, encoding: .utf8)
  }

  private func appendSuffix(existingText: String, payload: String) -> String {
    if existingText.isEmpty { return payload + "\n" }
    if existingText.hasSuffix("\n") { return payload + "\n" }
    return "\n" + payload + "\n"
  }
}
