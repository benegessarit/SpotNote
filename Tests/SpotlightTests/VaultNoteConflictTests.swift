import Foundation
import Testing

@testable import Spotlight

/// The vault is multi-writer (Neovim, Hermes, crons). A debounced SpotNote
/// overwrite may only land when the note still matches what this session
/// last read or wrote; otherwise the external edit keeps the canonical
/// file and OUR text diverts to one timestamped conflict sibling.
@Suite("Vault note conflict safety")
struct VaultNoteConflictTests {
  @Test("external edit survives byte-for-byte; our text lands in one sibling")
  func externalEditWinsCanonicalFile() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let noteURL = dir.appending(path: "inbox.md")
    try "- alpha".write(to: noteURL, atomically: true, encoding: .utf8)

    let document = VaultNoteDocument(url: noteURL, debounce: .milliseconds(5))
    _ = await document.load()

    let external = "- alpha\n- edited elsewhere"
    try writeExternally(external, to: noteURL)

    await document.update(text: "- alpha\n- typed in spotnote")
    await document.flush()

    #expect(try String(contentsOf: noteURL, encoding: .utf8) == external)
    let sibling = try #require(conflictSiblings(in: dir).first)
    let siblingText = try String(contentsOf: sibling, encoding: .utf8)
    #expect(siblingText == "- alpha\n- typed in spotnote")
    #expect(Set(siblingText.split(separator: "\n")).count == 2)
  }

  @Test("clean path still writes through and produces no sibling")
  func cleanPathWritesThrough() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let noteURL = dir.appending(path: "inbox.md")
    try "- alpha".write(to: noteURL, atomically: true, encoding: .utf8)

    let document = VaultNoteDocument(url: noteURL, debounce: .milliseconds(5))
    _ = await document.load()
    await document.update(text: "- alpha\n- beta")
    await document.flush()

    #expect(try String(contentsOf: noteURL, encoding: .utf8) == "- alpha\n- beta")
    #expect(conflictSiblings(in: dir).isEmpty)

    // Our own write must update the remembered mtime: a second clean
    // update keeps writing through instead of self-conflicting.
    await document.update(text: "- alpha\n- beta\n- gamma")
    await document.flush()
    #expect(try String(contentsOf: noteURL, encoding: .utf8) == "- alpha\n- beta\n- gamma")
    #expect(conflictSiblings(in: dir).isEmpty)
  }

  @Test("a conflict episode reuses one sibling across later keystrokes")
  func conflictEpisodeReusesSibling() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let noteURL = dir.appending(path: "inbox.md")
    try "- alpha".write(to: noteURL, atomically: true, encoding: .utf8)

    let document = VaultNoteDocument(url: noteURL, debounce: .milliseconds(5))
    _ = await document.load()
    try writeExternally("- alpha\n- external", to: noteURL)

    await document.update(text: "- mine v1")
    await document.flush()
    await document.update(text: "- mine v2")
    await document.flush()

    let siblings = conflictSiblings(in: dir)
    #expect(siblings.count == 1)
    let sibling = try #require(siblings.first)
    #expect(try String(contentsOf: sibling, encoding: .utf8) == "- mine v2")
    #expect(try String(contentsOf: noteURL, encoding: .utf8) == "- alpha\n- external")
  }

  @Test("an existing file this session never read is not clobbered")
  func unreadExistingFileIsNotClobbered() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let noteURL = dir.appending(path: "inbox.md")
    try "- preexisting".write(to: noteURL, atomically: true, encoding: .utf8)

    let document = VaultNoteDocument(url: noteURL, debounce: .milliseconds(5))
    await document.update(text: "- typed blind")
    await document.flush()

    #expect(try String(contentsOf: noteURL, encoding: .utf8) == "- preexisting")
    let sibling = try #require(conflictSiblings(in: dir).first)
    #expect(try String(contentsOf: sibling, encoding: .utf8) == "- typed blind")
  }

  // MARK: - Helpers

  private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(
      path: "vault-conflict-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Simulates another writer: replaces the content and pushes the mtime
  /// clearly past the document's remembered stamp so the check never
  /// depends on sub-millisecond filesystem timing.
  private func writeExternally(_ text: String, to url: URL) throws {
    try text.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(2)],
      ofItemAtPath: url.path
    )
  }

  private func conflictSiblings(in dir: URL) -> [URL] {
    let contents =
      (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    return contents.filter { $0.lastPathComponent.contains(".conflict-") }
  }
}
