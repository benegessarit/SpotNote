import AppKit
import Combine
import Foundation

/// User-customizable keyboard chord. The `key` is stored as a normalized
/// lowercase string ("n", "z", ",", "/", "space") so equality across
/// recordings and lookups is deterministic regardless of how AppKit
/// reports the character.
public struct Shortcut: Codable, Hashable, Sendable {
  public let key: String
  public let modifiers: ShortcutModifierSet

  public init(key: String, modifiers: ShortcutModifierSet) {
    self.key = Self.normalize(key)
    self.modifiers = modifiers
  }

  public var displayString: String {
    modifiers.displayString + Self.displayKey(key)
  }

  /// Normalizes characters reported by
  /// `NSEvent.charactersIgnoringModifiers` into the canonical form used
  /// as map keys.
  public static func normalize(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower == " " { return "space" }
    return lower
  }

  static func displayKey(_ key: String) -> String {
    switch key {
    case "space": return "Space"
    case "tab": return "Tab"
    case "return": return "Return"
    case "escape": return "Esc"
    default: return key.uppercased()
    }
  }
}

public struct ShortcutModifierSet: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let command = ShortcutModifierSet(rawValue: 1 << 0)
  public static let shift = ShortcutModifierSet(rawValue: 1 << 1)
  public static let option = ShortcutModifierSet(rawValue: 1 << 2)
  public static let control = ShortcutModifierSet(rawValue: 1 << 3)

  public init(_ flags: NSEvent.ModifierFlags) {
    var set: ShortcutModifierSet = []
    if flags.contains(.command) { set.insert(.command) }
    if flags.contains(.shift) { set.insert(.shift) }
    if flags.contains(.option) { set.insert(.option) }
    if flags.contains(.control) { set.insert(.control) }
    self = set
  }

  /// Canonical macOS modifier glyph order: ⌃⌥⇧⌘.
  public var displayString: String {
    var output = ""
    if contains(.control) { output += "⌃" }
    if contains(.option) { output += "⌥" }
    if contains(.shift) { output += "⇧" }
    if contains(.command) { output += "⌘" }
    return output
  }
}

public enum ShortcutAction: String, CaseIterable, Codable, Sendable, Identifiable {
  case toggleHotkey
  case appendToLastNote
  case insertTodayBadge
  case sendToLinear
  case appendToDailyNote
  case findInNote
  case copyContent
  case openSettings
  case newNote
  case browseNotes
  case duplicateNote
  case togglePin
  case goBack
  case goForward

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .toggleHotkey: return "Open Tasks / hide HUD"
    case .appendToLastNote: return "Open Tasks at end"
    case .insertTodayBadge: return "Insert today badge"
    case .sendToLinear: return "Send task to Linear"
    case .appendToDailyNote: return "Append line to Daily Note"
    case .findInNote: return "Find in note"
    case .copyContent: return "Copy note"
    case .openSettings: return "Open settings"
    case .newNote: return "New note"
    case .browseNotes: return "Browse notes"
    case .duplicateNote: return "Duplicate note"
    case .togglePin: return "Pin note"
    case .goBack: return "Go back"
    case .goForward: return "Go forward"
    }
  }

  public var subtitle: String {
    switch self {
    case .toggleHotkey: return "Global hotkey to summon the Tasks list from any app."
    case .appendToLastNote:
      return "Summon the Tasks note with the caret already at the end."
    case .insertTodayBadge: return "Insert @today token at the caret."
    case .sendToLinear: return "Create one Linear task from the current bullet, then delete it after handoff."
    case .appendToDailyNote:
      return "Append current or counted lines to today's vault daily note, then delete them after handoff."
    case .findInNote: return "Search for text inside the current note."
    case .copyContent: return "Copy the whole note. With a selection, copies just the selection."
    case .openSettings: return "Open this settings window."
    case .newNote: return "Save the current note and open a fresh blank one."
    case .browseNotes: return "Open the Browse Notes menu."
    case .duplicateNote: return "Open a new note carrying a copy of the current one."
    case .togglePin: return "Pin or unpin the current note; pinned notes sort first when browsing."
    case .goBack: return "Return to the previously open note."
    case .goForward: return "Redo a Go Back, returning to the newer note."
    }
  }

  public var defaultShortcut: Shortcut {
    switch self {
    case .toggleHotkey: return Shortcut(key: "space", modifiers: [.command, .shift])
    case .appendToLastNote: return Shortcut(key: ".", modifiers: [.command, .shift])
    case .insertTodayBadge: return Shortcut(key: "t", modifiers: [.command, .shift])
    case .sendToLinear: return Shortcut(key: "l", modifiers: [.command, .option])
    case .appendToDailyNote: return Shortcut(key: "d", modifiers: [.command, .option])
    case .findInNote: return Shortcut(key: "f", modifiers: [.command])
    case .copyContent: return Shortcut(key: "c", modifiers: [.command])
    case .openSettings: return Shortcut(key: ",", modifiers: [.command])
    // Raycast Notes parity: ⌘N new, ⌘P browse, ⌘D duplicate, ⇧⌘P pin,
    // ⌘[ back, ⌘] forward.
    case .newNote: return Shortcut(key: "n", modifiers: [.command])
    case .browseNotes: return Shortcut(key: "p", modifiers: [.command])
    case .duplicateNote: return Shortcut(key: "d", modifiers: [.command])
    case .togglePin: return Shortcut(key: "p", modifiers: [.command, .shift])
    case .goBack: return Shortcut(key: "[", modifiers: [.command])
    case .goForward: return Shortcut(key: "]", modifiers: [.command])
    }
  }

  var defaultShortcutCandidates: [Shortcut] {
    switch self {
    case .appendToDailyNote:
      return [
        defaultShortcut,
        Shortcut(key: "d", modifiers: [.command, .option, .shift])
      ]
    default:
      return [defaultShortcut]
    }
  }
}

/// Persistent, observable map of `ShortcutAction -> Shortcut`. Refuses
/// rebinds that collide with another action (so the user can't double-
/// book a chord) or that drop the modifier (which would shadow plain
/// typing). Persists to `UserDefaults` on every successful change.
@MainActor
public final class ShortcutStore: ObservableObject {
  public enum SetResult: Equatable {
    case ok
    case conflict(ShortcutAction)
    case missingModifier
  }

  @Published public private(set) var bindings: [ShortcutAction: Shortcut] = [:]

  private let defaults: UserDefaults
  private let storageKey: String

  public init(defaults: UserDefaults = .standard, storageKey: String = "shortcuts.bindings.v5") {
    self.defaults = defaults
    self.storageKey = storageKey
    self.bindings = Self.load(defaults: defaults, key: storageKey)
    persist()
  }

  public func binding(for action: ShortcutAction) -> Shortcut {
    bindings[action] ?? action.defaultShortcut
  }

  @discardableResult
  public func setBinding(_ shortcut: Shortcut, for action: ShortcutAction) -> SetResult {
    guard !shortcut.modifiers.isEmpty else { return .missingModifier }
    if let other = bindings.first(where: { $0.key != action && $0.value == shortcut })?.key {
      return .conflict(other)
    }
    bindings[action] = shortcut
    persist()
    return .ok
  }

  @discardableResult
  public func reset(_ action: ShortcutAction) -> SetResult {
    setBinding(action.defaultShortcut, for: action)
  }

  public func resetAll() {
    var rebuilt: [ShortcutAction: Shortcut] = [:]
    for action in ShortcutAction.allCases {
      rebuilt[action] = action.defaultShortcut
    }
    bindings = rebuilt
    persist()
  }

  public func match(key: String, modifiers: ShortcutModifierSet) -> ShortcutAction? {
    let lookup = Shortcut(key: key, modifiers: modifiers)
    return bindings.first(where: { $0.value == lookup })?.key
  }

  private static func load(defaults: UserDefaults, key: String) -> [ShortcutAction: Shortcut] {
    var loaded: [ShortcutAction: Shortcut] = [:]
    let data = defaults.data(forKey: key)
    let decoded = data.flatMap { try? JSONDecoder().decode([String: Shortcut].self, from: $0) }
    if let decoded {
      for (raw, shortcut) in decoded {
        if let action = ShortcutAction(rawValue: raw) {
          loaded[action] = shortcut
        }
      }
    }
    var result: [ShortcutAction: Shortcut] = [:]
    let alreadyOwned = Set(loaded.values)
    for action in ShortcutAction.allCases {
      if let shortcut = loaded[action] {
        result[action] = shortcut
      } else {
        result[action] = firstAvailableCandidate(for: action, avoiding: alreadyOwned.union(result.values))
      }
    }
    return result
  }

  private static func firstAvailableCandidate(
    for action: ShortcutAction,
    avoiding used: Set<Shortcut>
  ) -> Shortcut {
    action.defaultShortcutCandidates.first { !used.contains($0) } ?? action.defaultShortcut
  }

  private func persist() {
    var raw: [String: Shortcut] = [:]
    for (action, shortcut) in bindings {
      raw[action.rawValue] = shortcut
    }
    if let data = try? JSONEncoder().encode(raw) {
      defaults.set(data, forKey: storageKey)
    }
  }
}
