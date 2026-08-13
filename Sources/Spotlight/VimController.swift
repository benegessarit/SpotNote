import AppKit
import Combine
import SwiftUI

@MainActor
final class VimController: ObservableObject {
  enum PromptKind: Equatable {
    case command
    case search
    case flash(VimFlashDirection, count: Int, scope: VimFlashScope)
    case lineFlash(count: Int)
    case wordHint
  }

  enum MessageKind: Equatable { case info, success, error }
  enum MessageIcon: Equatable { case hermes }

  struct Message: Equatable {
    let text: String
    let kind: MessageKind
    var icon: MessageIcon?

    init(text: String, kind: MessageKind, icon: MessageIcon? = nil) {
      self.text = text
      self.kind = kind
      self.icon = icon
    }
  }

  struct Prompt: Equatable {
    let kind: PromptKind
    var buffer: String
  }

  @Published var mode: VimMode = .normal
  @Published var prompt: Prompt?
  @Published var message: Message?
  /// Sticky status from the last `/` search or `n`/`N` step (e.g.
  /// "2/5", "no matches"). Cleared on `:noh` or when a new search runs.
  @Published var searchStatus: String?

  /// Editor-side handlers wired by `PlaceholderTextView` once it has a
  /// reference to the live text view. They are reset to `nil` when the
  /// HUD closes so we don't leak the AppKit view across panel teardowns.
  var lineJumpHandler: ((Int) -> Bool)?
  var substituteHandler: ((SubstituteRequest) -> Int)?
  /// `\f` / `:fmt` -- tidy header spacing; returns whether anything changed.
  var normalizeHandler: (() -> Bool)?

  /// Top-level command runner installed by the `SpotlightWindowController`
  /// so commands can reach the session, find controller, theme catalog,
  /// and the close-HUD path.
  var commandRunner: ((VimCommand) -> Message?)?

  /// `:noh` reaches the view-owned vim search lane through this handler
  /// (installed by the live text view alongside the others).
  var searchClearHandler: (() -> Void)?
  /// One-character Flash-style jump handler installed by the live text view.
  /// Returns `true` when the caret moved.
  var flashHandler: ((VimFlashRequest) -> Bool)?

  private var messageClearTask: Task<Void, Never>?
  private static let messageDuration: Duration = .seconds(2)

  func updateMode(_ newMode: VimMode) {
    if mode != newMode { mode = newMode }
    if newMode == .insert {
      if prompt != nil { prompt = nil }
      // Search counters refer to a stale match index the moment the user
      // starts editing -- drop them so they don't linger as a confusing
      // "2/5" while typing unrelated text.
      if searchStatus != nil { searchStatus = nil }
    }
  }

  func enterPrompt(_ kind: PromptKind) {
    prompt = Prompt(kind: kind, buffer: "")
    message = nil
    messageClearTask?.cancel()
    messageClearTask = nil
  }

  func cancelPrompt() {
    prompt = nil
  }

  func appendToPrompt(_ text: String) {
    guard var current = prompt else { return }
    current.buffer.append(text)
    prompt = current
  }

  /// Wholesale buffer replacement for cmdline-style edits (Ctrl-W word
  /// delete, Ctrl-U clear) that appendToPrompt/backspacePrompt can't
  /// express. Keeps the prompt OPEN even when the buffer empties.
  func replacePromptBuffer(_ buffer: String) {
    guard var current = prompt else { return }
    current.buffer = buffer
    prompt = current
  }

  /// vim's cmdline chord edits (c_CTRL-W / c_CTRL-U), one rule for
  /// every prompt kind: the new buffer for the chord, or nil when the
  /// chord only swallows. Callers must consume the event either way --
  /// falling through would reach the editor's own word delete at a
  /// caret the user never chose.
  static func promptBufferEdit(controlChord chars: String, buffer: String) -> String? {
    switch chars {
    case "w": return SearchTextEditing.deleteWordBackward(buffer)
    case "u": return ""
    default: return nil
    }
  }

  func backspacePrompt() {
    guard var current = prompt else { return }
    if current.buffer.isEmpty {
      prompt = nil
      return
    }
    current.buffer.removeLast()
    prompt = current
  }

  /// Returns `true` if the prompt was submitted (and therefore should be
  /// dismissed by the caller); always dismisses on completion.
  @discardableResult
  func submitPrompt() -> Bool {
    guard let current = prompt else { return false }
    let buffer = current.buffer
    prompt = nil
    switch current.kind {
    case .command:
      let trimmed = buffer.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { return true }
      runCommand(trimmed)
    case .search, .flash, .lineFlash, .wordHint:
      // These prompt kinds are fully handled by the view-side key
      // routers; the generic submit path never fires for them.
      return true
    }
    return true
  }

  func submitFlash(_ query: String) {
    guard let current = prompt,
      case .flash(let direction, let count, let scope) = current.kind
    else { return }
    prompt = nil
    guard !query.isEmpty else { return }
    let request = VimFlashRequest(query: query, direction: direction, count: count, scope: scope)
    if flashHandler?(request) == true {
      message = nil
    } else {
      showMessage("flash: no match", kind: .error)
    }
  }

  func clearSearchStatus() {
    searchStatus = nil
  }

  /// Live counter from the vim search lane ("3/12", "3/500+",
  /// "no matches").
  func setSearchStatus(current: Int, total: Int, capped: Bool) {
    if total > 0 {
      searchStatus = "\(current)/\(total)\(capped ? "+" : "")"
    } else {
      searchStatus = "no matches"
    }
  }

  func showMessage(_ text: String, kind: MessageKind, icon: MessageIcon? = nil) {
    let msg = Message(text: text, kind: kind, icon: icon)
    message = msg
    messageClearTask?.cancel()
    let duration = Self.messageDuration
    messageClearTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      if self?.message == msg { self?.message = nil }
    }
  }

  func runCommand(_ raw: String) {
    let parsed = VimCommandParser.parse(raw)
    switch parsed {
    case .invalid(let text):
      showMessage(text, kind: .error)
    case .valid(let command):
      let result = commandRunner?(command)
      if let result {
        showMessage(result.text, kind: result.kind)
      }
    }
  }
}

// MARK: - Commands

enum VimCommand: Equatable {
  case quit
  case writeNoOp
  case setVimMode(Bool)
  case setTheme(String)
  case setMaxLines(Int)
  case substitute(SubstituteRequest)
  case gotoLine(Int)
  case clearHighlight
  case formatDocument
  case help
}

struct SubstituteRequest: Equatable {
  /// `true` when prefixed with `%` (operate on whole text). `false` is
  /// "current line only" -- driven by the editor's caret position.
  let global: Bool
  /// `true` when the trailing `g` flag is present (replace every
  /// occurrence in the chosen range, not just the first per line).
  let replaceAll: Bool
  let pattern: String
  let replacement: String
}

enum VimCommandParseResult {
  case valid(VimCommand)
  case invalid(String)
}

enum VimCommandParser {
  /// Static lookup for headword commands. Keeping this off the
  /// switch-statement keeps `parse` under the cyclomatic-complexity cap.
  private static let headwordTable: [String: VimCommand] = [
    "q": .quit, "quit": .quit, "x": .quit,
    "w": .writeNoOp, "write": .writeNoOp, "wq": .writeNoOp,
    "noh": .clearHighlight, "nohlsearch": .clearHighlight,
    "fmt": .formatDocument, "format": .formatDocument,
    "h": .help, "help": .help
  ]

  static func parse(_ raw: String) -> VimCommandParseResult {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return .invalid(notACommand(trimmed)) }
    if let line = Int(trimmed), line > 0 { return .valid(.gotoLine(line)) }
    if trimmed.hasPrefix("s/") { return parseSubstitute(trimmed, global: false) }
    if trimmed.hasPrefix("%s/") {
      return parseSubstitute(String(trimmed.dropFirst()), global: true)
    }
    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let head = String(parts[0])
    let argument = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
    if head == "set" { return parseSet(argument) }
    if let command = headwordTable[head] { return .valid(command) }
    return .invalid(notACommand(trimmed))
  }

  private static func parseSet(_ argument: String) -> VimCommandParseResult {
    let pieces = argument.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let first = pieces.first.map(String.init), !first.isEmpty else {
      return .invalid("E518: unknown option")
    }
    let value = pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespaces) : ""
    if let toggle = setToggleTable[first] { return .valid(toggle) }
    return parseSetParameterized(first, value: value)
  }

  /// Boolean `:set` flags. Every entry here is a no-argument toggle.
  private static let setToggleTable: [String: VimCommand] = [
    "vim": .setVimMode(true), "novim": .setVimMode(false)
  ]

  private static func parseSetParameterized(
    _ option: String,
    value: String
  ) -> VimCommandParseResult {
    switch option {
    case "theme":
      guard !value.isEmpty else { return .invalid("E518: theme name required") }
      return .valid(.setTheme(value))
    case "lines":
      guard let count = Int(value), count > 0 else {
        return .invalid("E518: lines must be a positive integer")
      }
      return .valid(.setMaxLines(count))
    default:
      return .invalid("E518: unknown option: \(option)")
    }
  }

  private static func parseSubstitute(_ raw: String, global: Bool) -> VimCommandParseResult {
    // `s/pattern/replacement/flags` -- split on `/`, no escape handling.
    let body = String(raw.dropFirst(2))  // strip `s/`
    let segments = body.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard segments.count >= 2 else {
      return .invalid("E486: invalid substitute syntax")
    }
    let pattern = segments[0]
    let replacement = segments[1]
    let flags = segments.count >= 3 ? segments[2] : ""
    guard !pattern.isEmpty else { return .invalid("E486: pattern required") }
    let replaceAll = flags.contains("g")
    return .valid(
      .substitute(
        SubstituteRequest(
          global: global,
          replaceAll: replaceAll,
          pattern: pattern,
          replacement: replacement
        )
      )
    )
  }

  private static func notACommand(_ raw: String) -> String {
    "E492: not an editor command: \(raw)"
  }
}

// MARK: - Reference catalog

/// Static reference list of every command supported by `VimCommandParser`.
/// Surfaced in the Settings -> Vim pane so users have a single source of
/// truth for what the prompt accepts.
enum VimCommandReference {
  struct Entry: Identifiable {
    let id: String
    let usage: String
    let summary: String
  }

  struct Section: Identifiable {
    let id: String
    let title: String
    let entries: [Entry]
  }

  static let sections: [Section] = [
    Section(
      id: "lifecycle",
      title: "Lifecycle",
      entries: [
        Entry(
          id: "q",
          usage: ":q\n:quit",
          summary: "Close the HUD."
        ),
        Entry(
          id: "w",
          usage: ":w\n:write",
          summary: "Symbolic. Left it in because some people have the muscle memory."
        ),
        Entry(
          id: "wq",
          usage: ":wq",
          summary: "Symbolic. Left it in because some people have the muscle memory."
        ),
        Entry(
          id: "x",
          usage: ":x",
          summary: "Close the HUD."
        )
      ]
    ),
    Section(
      id: "settings",
      title: "Settings (:set)",
      entries: [
        Entry(
          id: "vim",
          usage: ":set vim\n:set novim",
          summary: "Toggle vim mode itself. `:set novim` exits vim entirely."
        ),
        Entry(
          id: "theme",
          usage: ":set theme <name>",
          summary: "Switch theme by name (e.g. `obsidian`, `parchment`)."
        ),
        Entry(
          id: "lines",
          usage: ":set lines <n>",
          summary: "Maximum visible rows before the editor starts scrolling."
        )
      ]
    ),
    Section(
      id: "search",
      title: "Search & navigation",
      entries: [
        Entry(
          id: "subst",
          usage: ":s/foo/bar/[g]\n:%s/foo/bar/[g]",
          summary: "Substitute. `%` operates on the whole note, `g` on every match."
        ),
        Entry(
          id: "linejump",
          usage: ":<n>\n<n>G",
          summary: "Jump caret to line n."
        ),
        Entry(
          id: "section-jumps",
          usage: ",d\n,t",
          summary:
            "Jump to a fresh bullet in `## Todo` (,d) or `## Tray` (,t) and start typing;"
            + " the section is created if absent."
        ),
        Entry(
          id: "leader",
          usage: "\\t\n\\c\n\\f",
          summary:
            "`\\` leader: `\\t` appends the current line to spotnote-tray.md;"
            + " `\\c` appends the current bullet to the hermes-build State.md (clears it after);"
            + " `\\f` (or `:fmt`) tidies blank-line spacing around section headers."
        ),
        Entry(
          id: "noh",
          usage: ":noh\n:nohlsearch",
          summary: "Clear the active search highlight and counter."
        ),
        Entry(
          id: "slash",
          usage: "/<pattern>",
          summary: "Vim-native search. Matches highlight in the editor; the bottom bar shows `i/total`."
        ),
        Entry(
          id: "n",
          usage: "n  ·  N",
          summary: "Next / previous match in the active search."
        )
      ]
    ),
    Section(
      id: "help",
      title: "Help",
      entries: [
        Entry(
          id: "help",
          usage: ":h\n:help",
          summary: "Show a short help reminder."
        )
      ]
    )
  ]
}
