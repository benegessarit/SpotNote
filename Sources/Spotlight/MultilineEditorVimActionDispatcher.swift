import AppKit

/// Side-effect dispatcher for the simple `VimAction` cases (no associated
/// values that change the editor's text). Returning `true` tells
/// `executeVimAction` it has nothing more to do.
enum VimActionDispatcher {
  @MainActor
  static func handleSimple(_ action: VimAction, on view: PlaceholderTextView) -> Bool {
    if handleModeAction(action, on: view) { return true }
    if handlePromptAction(action, on: view) { return true }
    return handleEditingAction(action, on: view)
  }

  @MainActor
  private static func handleModeAction(
    _ action: VimAction,
    on view: PlaceholderTextView
  ) -> Bool {
    switch action {
    case .none:
      return true
    case .switchToInsert, .switchToNormal:
      // Collapse any lingering visual-line selection back to the
      // motion's last caret so Esc/V from VISUAL LINE leaves the user
      // exactly where they were, not on a wide highlight.
      if let caret = view.visualLineCaret ?? view.visualCaret {
        let clamped = min(caret, (view.string as NSString).length)
        view.setSelectedRange(NSRange(location: clamped, length: 0))
      }
      view.visualAnchor = nil
      view.visualCaret = nil
      view.visualLineAnchor = nil
      view.visualLineCaret = nil
      view.notifyVimModeChanged()
      view.needsDisplay = true
    case .insertAtEndOfLine:
      view.moveToEndOfLine(view)
      view.notifyVimModeChanged()
      view.needsDisplay = true
    case .insertAtFirstNonBlank:
      view.executeMotion(.firstNonBlank)
      view.notifyVimModeChanged()
      view.needsDisplay = true
    default:
      return false
    }
    return true
  }

  @MainActor
  private static func handlePromptAction(
    _ action: VimAction,
    on view: PlaceholderTextView
  ) -> Bool {
    switch action {
    case .enterCommand: view.vimController?.enterPrompt(.command)
    case .enterSearch: view.vimController?.enterPrompt(.search)
    case .enterFlash(let direction, let count, let scope):
      view.enterFlashPrompt(direction: direction, count: count, scope: scope)
    case .enterLineFlash(let count):
      view.vimController?.enterPrompt(.lineFlash(count: count))
      view.refreshLineFlashHints()
    case .findNext: view.vimController?.findStep(1)
    case .findPrevious: view.vimController?.findStep(-1)
    default: return false
    }
    return true
  }

  @MainActor
  private static func handleEditingAction(
    _ action: VimAction,
    on view: PlaceholderTextView
  ) -> Bool {
    switch action {
    case .deleteToEndOfLine:
      view.deleteToEndOfParagraph(view)
    case .openLineBelow:
      view.openLineBelowForVim()
      view.notifyVimModeChanged()
      view.needsDisplay = true
    case .openLineAbove:
      view.openLineAboveForVim()
      view.notifyVimModeChanged()
      view.needsDisplay = true
    default:
      return false
    }
    return true
  }
}
