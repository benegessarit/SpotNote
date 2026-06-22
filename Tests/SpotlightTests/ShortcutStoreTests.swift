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
      for: .newChat
    )
    #expect(result == .ok)
    #expect(store.binding(for: .newChat).key == "j")
  }

  @Test("rebind to a chord owned by another action returns conflict")
  func rebindConflict() {
    let store = ShortcutStore(defaults: makeDefaults())
    // Default `.newChat` is ⌘N. Try to assign that to `.openSettings`.
    let result = store.setBinding(
      Shortcut(key: "n", modifiers: [.command]),
      for: .openSettings
    )
    #expect(result == .conflict(.newChat))
    #expect(store.binding(for: .openSettings).key == ",", "binding stays at default on conflict")
  }

  @Test("modifier-less chords are rejected")
  func rejectsBareKey() {
    let store = ShortcutStore(defaults: makeDefaults())
    let result = store.setBinding(Shortcut(key: "n", modifiers: []), for: .newChat)
    #expect(result == .missingModifier)
  }

  @Test("bindings persist across store instances")
  func persistsAcrossInstances() {
    let defaults = makeDefaults()
    let first = ShortcutStore(defaults: defaults)
    _ = first.setBinding(
      Shortcut(key: "j", modifiers: [.command, .option]),
      for: .deleteChat
    )
    let second = ShortcutStore(defaults: defaults)
    #expect(second.binding(for: .deleteChat).key == "j")
    #expect(second.binding(for: .deleteChat).modifiers == [.command, .option])
  }

  @Test("match resolves the action that owns a chord, ignoring others")
  func matchResolvesOwner() {
    let store = ShortcutStore(defaults: makeDefaults())
    let action = store.match(key: "n", modifiers: [.command])
    #expect(action == .newChat)
    let none = store.match(key: "j", modifiers: [.command])
    #expect(none == nil)
  }

  @Test("plain Cmd-K does not open the command palette")
  func commandPaletteDefaultAvoidsPlainCmdK() {
    let store = ShortcutStore(defaults: makeDefaults())

    #expect(ShortcutAction.commandPalette.defaultShortcut != Shortcut(key: "k", modifiers: [.command]))
    #expect(store.match(key: "k", modifiers: [.command]) == nil)
    #expect(store.match(key: "k", modifiers: [.command, .option]) == .commandPalette)
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

  @Test("legacy command palette Cmd-K binding migrates off plain Cmd-K")
  func legacyCommandPaletteCmdKBindingMigratesOffPlainCmdK() throws {
    let defaults = makeDefaults()
    let key = "shortcuts.bindings.v5"
    var oldMap: [String: Shortcut] = [:]
    for action in ShortcutAction.allCases {
      oldMap[action.rawValue] = action.defaultShortcut
    }
    oldMap[ShortcutAction.commandPalette.rawValue] = Shortcut(key: "k", modifiers: [.command])
    defaults.set(try JSONEncoder().encode(oldMap), forKey: key)

    let store = ShortcutStore(defaults: defaults, storageKey: key)

    #expect(store.match(key: "k", modifiers: [.command]) == nil)
    #expect(store.binding(for: .commandPalette) == ShortcutAction.commandPalette.defaultShortcut)
  }

  @Test("resetAll restores every action to its default")
  func resetAllRestoresDefaults() {
    let store = ShortcutStore(defaults: makeDefaults())
    _ = store.setBinding(
      Shortcut(key: "k", modifiers: [.command, .option]),
      for: .newChat
    )
    store.resetAll()
    #expect(store.binding(for: .newChat) == ShortcutAction.newChat.defaultShortcut)
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
