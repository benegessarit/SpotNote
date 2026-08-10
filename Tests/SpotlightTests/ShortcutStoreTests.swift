import Foundation
import Testing

@testable import Spotlight

@MainActor
@Suite("ShortcutStore")
struct ShortcutStoreTests {
  private func makeDefaults(_ tag: String = #function) -> UserDefaults {
    let suite = "spotnote.test.\(tag).\(UUID().uuidString)"
    return UserDefaults(suiteName: suite) ?? .standard
  }

  @Test("every action has a non-empty default chord")
  func defaultsCoverAllActions() {
    for action in ShortcutAction.allCases {
      let shortcut = action.defaultShortcut
      #expect(!shortcut.key.isEmpty)
      #expect(!shortcut.modifiers.isEmpty, "global plain-key chords would shadow typing")
    }
  }

  @Test("rebind succeeds when no other action owns the chord")
  func rebindSucceeds() {
    let store = ShortcutStore(defaults: makeDefaults())
    let result = store.setBinding(
      Shortcut(key: "j", modifiers: [.command, .shift]),
      for: .findInNote
    )
    #expect(result == .ok)
    #expect(store.binding(for: .findInNote).key == "j")
  }

  @Test("rebind to a chord owned by another action returns conflict")
  func rebindConflict() {
    let store = ShortcutStore(defaults: makeDefaults())
    // Default `.findInNote` is ⌘F. Try to assign that to `.openSettings`.
    let result = store.setBinding(
      Shortcut(key: "f", modifiers: [.command]),
      for: .openSettings
    )
    #expect(result == .conflict(.findInNote))
    #expect(store.binding(for: .openSettings).key == ",", "binding stays at default on conflict")
  }

  @Test("modifier-less chords are rejected")
  func rejectsBareKey() {
    let store = ShortcutStore(defaults: makeDefaults())
    let result = store.setBinding(Shortcut(key: "f", modifiers: []), for: .findInNote)
    #expect(result == .missingModifier)
  }

  @Test("bindings persist across store instances")
  func persistsAcrossInstances() {
    let defaults = makeDefaults()
    let first = ShortcutStore(defaults: defaults)
    _ = first.setBinding(
      Shortcut(key: "j", modifiers: [.command, .option]),
      for: .findInNote
    )
    let second = ShortcutStore(defaults: defaults)
    #expect(second.binding(for: .findInNote).key == "j")
    #expect(second.binding(for: .findInNote).modifiers == [.command, .option])
  }

  @Test("match resolves the action that owns a chord, ignoring others")
  func matchResolvesOwner() {
    let store = ShortcutStore(defaults: makeDefaults())
    let action = store.match(key: "f", modifiers: [.command])
    #expect(action == .findInNote)
    let none = store.match(key: "j", modifiers: [.command])
    #expect(none == nil)
  }

  @Test("retired one-note-incompatible shortcuts do not match")
  func retiredOneNoteShortcutsDoNotMatch() {
    let store = ShortcutStore(defaults: makeDefaults())

    #expect(store.match(key: "k", modifiers: [.command]) == nil)
    #expect(store.match(key: "k", modifiers: [.command, .option]) == nil)
    #expect(store.match(key: "s", modifiers: [.command]) == nil)
  }

  @Test("multi-note Raycast-parity shortcuts: Cmd N new note, Cmd P browse")
  func multiNoteShortcutsMatch() {
    let store = ShortcutStore(defaults: makeDefaults())

    // ⌘N/⌘P were retired in the one-note era; the multi-note browse and
    // actions menus revived them (2026-08-10) to match Raycast Notes.
    #expect(store.match(key: "n", modifiers: [.command]) == .newNote)
    #expect(store.match(key: "p", modifiers: [.command]) == .browseNotes)
    #expect(store.match(key: "d", modifiers: [.command]) == .duplicateNote)
    #expect(store.match(key: "p", modifiers: [.command, .shift]) == .togglePin)
    #expect(store.match(key: "[", modifiers: [.command]) == .goBack)
    #expect(store.match(key: "]", modifiers: [.command]) == .goForward)
  }

  @Test("send to Linear defaults to Cmd Option L")
  func sendToLinearDefaultShortcut() {
    let store = ShortcutStore(defaults: makeDefaults())
    let binding = store.binding(for: .sendToLinear)
    #expect(binding.key == "l")
    #expect(binding.modifiers == [.command, .option])
    #expect(store.match(key: "l", modifiers: [.command, .option]) == .sendToLinear)
  }

  @Test("append to Daily Note defaults to Cmd Option D")
  func appendToDailyNoteDefaultShortcut() {
    let store = ShortcutStore(defaults: makeDefaults())
    let binding = store.binding(for: .appendToDailyNote)
    #expect(binding.key == "d")
    #expect(binding.modifiers == [.command, .option])
    #expect(store.match(key: "d", modifiers: [.command, .option]) == .appendToDailyNote)
  }

  @Test("tray has no separate global open shortcut")
  func trayHasNoSeparateGlobalOpenShortcut() {
    let store = ShortcutStore(defaults: makeDefaults())
    #expect(store.match(key: "space", modifiers: [.command, .option]) == nil)
  }

  @Test("loading an older shortcut map avoids conflicts for new default chords")
  func missingActionBackfillAvoidsExistingChordConflicts() throws {
    let defaults = makeDefaults()
    let key = "shortcuts.bindings.v5"
    var oldMap: [String: Shortcut] = [:]
    for action in ShortcutAction.allCases where action != .appendToDailyNote {
      oldMap[action.rawValue] = action.defaultShortcut
    }
    let existingOwner = Shortcut(key: "d", modifiers: [.command, .option])
    oldMap[ShortcutAction.openSettings.rawValue] = existingOwner
    defaults.set(try JSONEncoder().encode(oldMap), forKey: key)

    let store = ShortcutStore(defaults: defaults, storageKey: key)

    #expect(store.binding(for: .openSettings) == existingOwner)
    #expect(store.binding(for: .appendToDailyNote) == Shortcut(key: "d", modifiers: [.command, .option, .shift]))
    #expect(store.match(key: "d", modifiers: [.command, .option]) == .openSettings)
    #expect(store.match(key: "d", modifiers: [.command, .option, .shift]) == .appendToDailyNote)
  }

  @Test("loading an older shortcut map writes missing actions back to defaults")
  func missingActionsArePersistedBackToDefaults() throws {
    let defaults = makeDefaults()
    let key = "shortcuts.bindings.v5"
    var oldMap: [String: Shortcut] = [:]
    for action in ShortcutAction.allCases where ![.sendToLinear, .appendToDailyNote].contains(action) {
      oldMap[action.rawValue] = action.defaultShortcut
    }
    defaults.set(try JSONEncoder().encode(oldMap), forKey: key)

    _ = ShortcutStore(defaults: defaults, storageKey: key)

    let storedData = try #require(defaults.data(forKey: key))
    let stored = try JSONDecoder().decode([String: Shortcut].self, from: storedData)
    #expect(stored[ShortcutAction.sendToLinear.rawValue] == ShortcutAction.sendToLinear.defaultShortcut)
    #expect(stored[ShortcutAction.appendToDailyNote.rawValue] == ShortcutAction.appendToDailyNote.defaultShortcut)
  }

  @Test("retired shortcut actions are dropped from stored bindings")
  func retiredShortcutActionsAreDroppedFromStoredBindings() throws {
    let defaults = makeDefaults()
    let key = "shortcuts.bindings.v5"
    var oldMap: [String: Shortcut] = [:]
    for action in ShortcutAction.allCases {
      oldMap[action.rawValue] = action.defaultShortcut
    }
    oldMap["commandPalette"] = Shortcut(key: "k", modifiers: [.command, .option])
    oldMap["pinNote"] = Shortcut(key: "s", modifiers: [.command])
    oldMap["newChat"] = Shortcut(key: "n", modifiers: [.command])
    oldMap["fuzzyFindAll"] = Shortcut(key: "p", modifiers: [.command])
    defaults.set(try JSONEncoder().encode(oldMap), forKey: key)

    _ = ShortcutStore(defaults: defaults, storageKey: key)
    let storedData = try #require(defaults.data(forKey: key))
    let stored = try JSONDecoder().decode([String: Shortcut].self, from: storedData)

    #expect(stored["commandPalette"] == nil)
    #expect(stored["pinNote"] == nil)
    #expect(stored["newChat"] == nil)
    #expect(stored["fuzzyFindAll"] == nil)
  }

  @Test("resetAll restores every action to its default")
  func resetAllRestoresDefaults() {
    let store = ShortcutStore(defaults: makeDefaults())
    _ = store.setBinding(
      Shortcut(key: "k", modifiers: [.command, .option]),
      for: .findInNote
    )
    store.resetAll()
    #expect(store.binding(for: .findInNote) == ShortcutAction.findInNote.defaultShortcut)
  }

  @Test("normalize folds case and maps the bare space character to 'space'")
  func normalizes() {
    #expect(Shortcut.normalize("N") == "n")
    #expect(Shortcut.normalize(" ") == "space")
    #expect(Shortcut.normalize(",") == ",")
  }

  @Test("displayString renders modifiers in canonical macOS order")
  func displayStringOrder() {
    let chord = Shortcut(
      key: "space",
      modifiers: [.command, .control, .option, .shift]
    )
    #expect(chord.displayString == "⌃⌥⇧⌘Space")
  }
}
