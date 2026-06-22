import Foundation

/// Normal-mode pending-prefix dispatch for `VimEngine`, split out so `VimEngine.swift`
/// stays within its length budget. Three prefixes:
/// - `d`/`c`/`ci`: delete / change operators.
/// - `g`: Linear handoff (`gd/gp/gs/gt/gl`); `gg` keeps the document-start motion.
/// - `,`: section jumps (`,h/,d/,t/,b`) that drop into insert on a fresh bullet.
/// - `\`: reusable leader (`\t` tray-append, `\h` habit-log).
extension VimEngine {
  func handlePending(key: String) -> VimAction {
    let count = resolvedCount
    defer { clearAccumulator() }

    switch pendingBuffer {
    case "d": return handlePendingD(key: key, count: count)
    case "c": return handlePendingC(key: key, count: count)
    case "ci": return handlePendingCI(key: key)
    case "g": return handlePendingG(key: key, count: count)
    case ",": return handlePendingComma(key: key)
    case "\\": return handlePendingBackslash(key: key, count: count)
    default:
      pendingBuffer = ""
      return .none
    }
  }

  private func handlePendingD(key: String, count: Int) -> VimAction {
    pendingBuffer = ""
    if key == "d" { return .deleteLine(count: count) }
    if let motion = motionForKey(key, count: count) { return .delete(motion) }
    return .none
  }

  private func handlePendingC(key: String, count: Int) -> VimAction {
    if key == "i" {
      pendingBuffer = "ci"
      return .none
    }
    pendingBuffer = ""
    if key == "c" {
      enterInsertMode()
      return .deleteLineInsert(count: count)
    }
    if key == "B" {
      enterInsertMode()
      return .changeBulletBody
    }
    if let motion = motionForKey(key, count: count) { return .delete(motion) }
    return .none
  }

  private func handlePendingCI(key: String) -> VimAction {
    pendingBuffer = ""
    if key == "b" {
      enterInsertMode()
      return .changeBulletBody
    }
    return .none
  }

  // `g` is the Linear handoff prefix: g + status sends the current bullet to
  // David's personal Linear at that state. `gg` keeps the document-start motion.
  private func handlePendingG(key: String, count: Int) -> VimAction {
    pendingBuffer = ""
    if key == "g" { return .moveCursor(.documentStart) }
    if key == "d" { return .sendCurrentTaskToLinear(status: .done, count: count) }
    if key == "p" { return .sendCurrentTaskToLinear(status: .planned, count: count) }
    if key == "t" { return .sendCurrentTaskToLinear(status: .triage, count: count) }
    if key == "s" { return .sendCurrentTaskToLinear(status: .started, count: count) }
    if key == "l" { return .sendCurrentTaskToLinear(status: .later, count: count) }
    return .none
  }

  // `,` is the section-jump prefix: jump to a `## …` section and drop into
  // insert on a fresh bullet (creating the section if absent).
  private func handlePendingComma(key: String) -> VimAction {
    pendingBuffer = ""
    if key == "h" { return jumpToSectionInsertAction(.jumpToHabitsSection) }
    if key == "d" { return jumpToSectionInsertAction(.jumpToToDoSection) }
    if key == "t" { return jumpToSectionInsertAction(.jumpToTraySection) }
    if key == "b" { return jumpToSectionInsertAction(.jumpToBigThingsSection) }
    return .none
  }

  // `\` is a reusable leader. `\t` appends the current line to tray.md;
  // `\h` logs the current `## Habits` bullet to the Life Dashboard habit tracker
  // (then clears the bullet, like the Linear handoff — David re-adds habits daily).
  private func handlePendingBackslash(key: String, count: Int) -> VimAction {
    pendingBuffer = ""
    if key == "t" { return .appendCurrentLineToTrayNote(count: count) }
    if key == "h" { return .sendCurrentHabitDone(count: count) }
    return .none
  }

  private func jumpToSectionInsertAction(_ action: VimAction) -> VimAction {
    enterInsertMode()
    return action
  }
}
