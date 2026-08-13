import AppKit

extension SpotlightWindowController {
  /// Wires the controller's command-runner closure so the `:`-prompt
  /// can reach the session, find controller, theme catalog,
  /// preferences, and the close-HUD path. (`/` search and `n`/`N` are
  /// fully view-owned -- MultilineEditorVimSearch.swift.)
  func installVimCommandRunner() {
    vimController.commandRunner = { [weak self] command in
      self?.runVimCommand(command)
    }
  }

  private func runVimCommand(_ command: VimCommand) -> VimController.Message? {
    switch command {
    case .quit:
      close()
      return nil
    case .writeNoOp:
      return VimController.Message(text: "No need. SpotNote autosaves.", kind: .info)
    case .substitute(let req):
      return runSubstitute(req)
    case .gotoLine(let line):
      return runGotoLine(line)
    case .clearHighlight:
      runClearHighlight()
      return nil
    case .formatDocument:
      return runFormat()
    case .help:
      return VimController.Message(text: "Vim help lives in Settings → Vim.", kind: .info)
    default:
      return runVimSetting(command)
    }
  }

  private func runVimSetting(_ command: VimCommand) -> VimController.Message? {
    switch command {
    case .setVimMode(let on):
      preferences.vimMode = on
      return on ? nil : VimController.Message(text: "vim mode off", kind: .info)
    case .setTheme(let name):
      return runSetTheme(name)
    case .setMaxLines(let count):
      let clamped = ThemePreferences.clampVisibleLines(count)
      preferences.maxVisibleLines = clamped
      return VimController.Message(text: "max lines: \(clamped)", kind: .info)
    default:
      return nil
    }
  }

  private func runSetTheme(_ name: String) -> VimController.Message? {
    let needle = name.lowercased()
    let match = ThemeCatalog.all.first {
      $0.id == needle || $0.name.lowercased() == needle
    }
    guard let match else {
      return VimController.Message(text: "E518: unknown theme: \(name)", kind: .error)
    }
    preferences.selectedThemeID = match.id
    return VimController.Message(text: "theme: \(match.name)", kind: .info)
  }

  private func runSubstitute(_ req: SubstituteRequest) -> VimController.Message? {
    let count = vimController.substituteHandler?(req) ?? 0
    if count == 0 {
      return VimController.Message(text: "E486: pattern not found", kind: .error)
    }
    let scope = req.global ? "in note" : "on line"
    let plural = count == 1 ? "" : "s"
    return VimController.Message(
      text: "\(count) substitution\(plural) \(scope)",
      kind: .success
    )
  }

  private func runFormat() -> VimController.Message? {
    let changed = vimController.normalizeHandler?() ?? false
    return VimController.Message(
      text: changed ? "Formatted" : "Already tidy",
      kind: changed ? .success : .info
    )
  }

  private func runGotoLine(_ line: Int) -> VimController.Message? {
    let ok = vimController.lineJumpHandler?(line) ?? false
    if !ok { return VimController.Message(text: "E16: invalid line: \(line)", kind: .error) }
    return nil
  }

  private func runClearHighlight() {
    if findController.isVisible {
      findController.close()
    }
    vimController.searchClearHandler?()
    vimController.clearSearchStatus()
  }
}
