import AppKit
import Combine
import SwiftUI

@MainActor
final class FocusTrigger: ObservableObject {
  @Published private(set) var tick: Int = 0
  /// Bumped to ask the editor to move its caret to the very end of the
  /// current note's text (editor-side plumbing kept for in-app callers).
  @Published private(set) var caretEndTick: Int = 0
  func pulse() { tick &+= 1 }
}

/// Published key-window state for the main panel, driving the Raycast
/// chrome's resigned look (lights/pill/theme button hide, title dims).
@MainActor
final class PanelKeyState: ObservableObject {
  @Published var isKey = false
}

struct SpotlightRootView: View {
  @ObservedObject var focusTrigger: FocusTrigger
  @ObservedObject var keyState: PanelKeyState
  @ObservedObject var preferences: ThemePreferences
  @ObservedObject var session: ChatSession
  @ObservedObject var shortcuts: ShortcutStore
  @ObservedObject var find: FindController
  @ObservedObject var fuzzy: FuzzyController
  let vimController: VimController
  /// Called synchronously from the editor delegate when the text's line
  /// count changes, so the panel resize happens in the same runloop tick
  /// as the text mutation (no flash).
  let onHeightChange: (CGFloat) -> Void
  /// Invoked when Esc should dismiss the HUD (vim off, or vim on and
  /// already in normal mode).
  let onEscape: () -> Void
  let onSendLinearTask: (LinearTaskHandoffRequest) async throws -> ScratchpadHandoffReceipt
  let onAppendDailyNote: (String) async throws -> URL
  let onAppendTrayNote: (String) async throws -> URL
  let onAppendStateNote: (String) async throws -> URL

  private var theme: Theme { preferences.activeTheme }

  private var editorFont: NSFont {
    SpotNoteFont.editor()
  }

  /// Binding that funnels user edits through `session.persistIfNeeded()`
  /// so they hit the debounced store writer. Programmatic chat-switches
  /// bypass this path by assigning `session.currentText` directly.
  private var editorText: Binding<String> {
    Binding(
      get: { session.currentText },
      set: { newValue in
        guard session.currentText != newValue else { return }
        session.currentText = newValue
        session.persistIfNeeded()
        if find.isVisible { find.search(in: newValue) }
      }
    )
  }

  /// Chrome the SwiftUI tree adds around the editor. Must mirror the
  /// window controller's `chromeAboveEditor + chromeBelowEditor`: the
  /// Raycast bars are always present; the find bar is conditional. The
  /// notes/actions modals float in an overlay and never change height.
  private var extraChromeHeight: CGFloat {
    var total = EditorMetrics.topBarHeight + EditorMetrics.bottomBarHeight
    if find.isVisible { total += EditorMetrics.findBarHeight }
    return total
  }

  @State private var actionsModalShown = false
  @State private var themePickerShown = false

  var body: some View {
    VStack(spacing: 0) {
      RaycastTopBar(
        title: noteTitle,
        theme: theme,
        isKey: keyState.isKey,
        onClose: onEscape,
        onShowActions: { actionsModalShown = true },
        onToggleNotes: { fuzzy.toggle(corpus: session.chats) },
        onNewNote: { newNote() }
      )
      if find.isVisible {
        FindBar(controller: find, theme: theme, editorText: session.currentText)
          .transition(.opacity)
      }
      editorCard
        .transaction { $0.animation = nil }
      RaycastBottomBar(
        characterCount: session.currentText.count,
        theme: theme,
        isKey: keyState.isKey,
        preferences: preferences,
        themePickerShown: $themePickerShown
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      SpotNoteVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        .clipShape(surfaceShape)
        .overlay(surfaceShape.fill(surfaceFill))
    }
    .overlay(modalLayer)
    .overlay(surfaceShape.strokeBorder(theme.border, lineWidth: 1))
    .colorScheme(theme.mode == .dark ? .dark : .light)
    .animation(.easeOut(duration: 0.10), value: find.isVisible)
    .onChange(of: session.chats) { _, updatedChats in
      fuzzy.updateCorpus(updatedChats)
    }
    .onChange(of: find.isVisible) { _, isVisible in
      if !isVisible { focusTrigger.pulse() }
    }
    .onChange(of: fuzzy.isVisible) { _, isVisible in
      if !isVisible { focusTrigger.pulse() }
    }
    .onChange(of: actionsModalShown) { _, isShown in
      if !isShown { focusTrigger.pulse() }
    }
    .onAppear {
      let editorHeight = EditorMetrics.panelHeight(
        forLines: EditorMetrics.lineCount(in: session.currentText),
        maxLines: preferences.maxVisibleLines
      )
      onHeightChange(editorHeight + extraChromeHeight)
    }
  }

  /// Floating Raycast-style modals over a dimmed note. Lives in an
  /// `.overlay` so showing a modal never touches the measured height tree.
  @ViewBuilder
  private var modalLayer: some View {
    if fuzzy.isVisible || actionsModalShown {
      ZStack(alignment: .top) {
        surfaceShape
          .fill(RaycastModalPalette.backdrop)
          .onTapGesture { dismissModals() }
        if fuzzy.isVisible {
          RaycastNotesModal(
            controller: fuzzy,
            currentChatID: session.currentID
          ) { chat in
            session.jump(to: chat)
          }
          .padding(.top, RaycastModalPalette.topOffset)
        } else {
          RaycastActionsModal(actions: modalActions, onClose: { actionsModalShown = false })
            .padding(.top, RaycastModalPalette.topOffset)
        }
      }
      .transition(.opacity)
    }
  }

  private var modalActions: [RaycastAction] {
    [
      RaycastAction(
        id: "new-note",
        title: "New Note",
        systemImage: "plus",
        keys: [],
        section: 0,
        perform: { newNote() }
      ),
      RaycastAction(
        id: "browse-notes",
        title: "Browse Notes",
        systemImage: "square.on.square",
        keys: [],
        section: 0,
        perform: { fuzzy.toggle(corpus: session.chats) }
      ),
      RaycastAction(
        id: "find-in-note",
        title: "Find in Note",
        systemImage: "magnifyingglass",
        keys: keycaps(for: .findInNote),
        section: 1,
        perform: { find.toggle(text: session.currentText) }
      ),
      RaycastAction(
        id: "copy-note",
        title: "Copy Note",
        systemImage: "doc.on.clipboard",
        keys: keycaps(for: .copyContent),
        section: 1,
        perform: {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(session.currentText, forType: .string)
        }
      ),
      RaycastAction(
        id: "change-theme",
        title: "Change Theme",
        systemImage: "paintpalette",
        keys: [],
        section: 2,
        perform: { themePickerShown = true }
      )
    ]
  }

  /// Keycap strings for the action's live (user-remappable) binding, e.g.
  /// ["⌘", "F"].
  private func keycaps(for action: ShortcutAction) -> [String] {
    let binding = shortcuts.binding(for: action)
    var caps = binding.modifiers.displayString.map(String.init)
    caps.append(Shortcut.displayKey(binding.key))
    return caps
  }

  private func newNote() {
    Task { @MainActor in
      await session.newNote()
      focusTrigger.pulse()
    }
  }

  private func dismissModals() {
    if fuzzy.isVisible { fuzzy.close() }
    actionsModalShown = false
  }

  /// First line of the current note, shown as the centered window title.
  private var noteTitle: String {
    let firstLine =
      session.currentText
      .components(separatedBy: "\n")
      .first?
      .trimmingCharacters(in: .whitespaces) ?? ""
    return firstLine.isEmpty ? "New Note" : firstLine
  }

  // Near-opaque tint: the panel should read as a solid surface with only a hint
  // of the blurred material behind it, not a translucent glass pane.
  static let darkGlassTintOpacity = 0.90
  static let lightGlassTintOpacity = 0.90

  private var glassTintOpacity: Double {
    theme.mode == .dark ? Self.darkGlassTintOpacity : Self.lightGlassTintOpacity
  }

  /// Full-bleed Raycast-style surface: one rounded rectangle for the whole
  /// panel; the bars and editor all sit on this single sheet.
  private var surfaceShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: EditorMetrics.surfaceCornerRadius, style: .continuous)
  }

  /// Themes with a `backgroundTop` render Raycast Notes' vertical top-lit
  /// gradient at full opacity; flat themes keep the near-opaque glass tint.
  private var surfaceFill: AnyShapeStyle {
    if let top = theme.backgroundTop {
      return AnyShapeStyle(
        LinearGradient(
          colors: [top, theme.background],
          startPoint: .top,
          endPoint: .bottom
        )
      )
    }
    return AnyShapeStyle(theme.background.opacity(glassTintOpacity))
  }

  private var editorCard: some View {
    MultilineEditor(
      text: editorText,
      checklistLines: session.currentChecklistLines,
      onChecklistLinesChange: { session.updateChecklistLines($0) },
      theme: theme,
      placeholder: editorPlaceholder,
      showLineNumbers: preferences.showLineNumbers,
      font: editorFont,
      focusRequest: focusTrigger.tick,
      caretEndRequest: focusTrigger.caretEndTick,
      maxVisibleLines: preferences.maxVisibleLines,
      extraChromeHeight: extraChromeHeight,
      findHighlight: find.currentMatch,
      vimModeEnabled: preferences.vimMode,
      vimController: vimController,
      onEscape: onEscape,
      onSendLinearTask: onSendLinearTask,
      onAppendDailyNote: onAppendDailyNote,
      onAppendTrayNote: onAppendTrayNote,
      onAppendStateNote: onAppendStateNote,
      onHeightChange: onHeightChange
    )
    .padding(.leading, EditorMetrics.leadingInset)
    .padding(.trailing, EditorMetrics.trailingInset)
    .padding(.vertical, EditorMetrics.verticalInset)
  }

  private var editorPlaceholder: String {
    switch session.currentVaultState {
    case .tasks: return "Add a task…"
    case nil: return "Jot something down…"
    }
  }

}
