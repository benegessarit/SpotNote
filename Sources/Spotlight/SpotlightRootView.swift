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
  /// Pointer-over-window state driving the hover-revealed traffic
  /// lights. A modal child window intercepts tracking events, so the
  /// lights also stay lit while any modal is up (like the live app).
  @State private var windowHovered = false

  var body: some View {
    mainColumn
      .frame(width: EditorMetrics.panelWidth)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        SpotNoteVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
          .clipShape(surfaceShape)
          .overlay(surfaceShape.fill(surfaceFill))
      }
      .overlay(modalLayer)
      .background(
        RaycastModalOverhang(
          content: anyModalShown ? AnyView(activeModal) : nil,
          onDismissTap: { dismissModals() }
        )
      )
      .overlay(surfaceShape.strokeBorder(theme.border, lineWidth: 1))
      .onHover { windowHovered = $0 }
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
      .onChange(of: themePickerShown) { _, isShown in
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

  /// The Raycast Notes column: bars and editor, always `panelWidth` wide.
  private var mainColumn: some View {
    VStack(spacing: 0) {
      RaycastTopBar(
        title: noteTitle,
        theme: theme,
        // The chrome stays lit while a modal child window holds key --
        // the live app keeps the close light red under its menus.
        isKey: keyState.isKey || anyModalShown,
        showsLights: windowHovered || anyModalShown,
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
      RaycastBottomBar(characterCount: session.currentText.count)
        .overlay(alignment: .trailing) {
          if preferences.vimMode {
            VimModePill(controller: vimController, isKey: keyState.isKey || anyModalShown)
              .padding(.trailing, 10)
          }
        }
    }
  }

  private func newNote() {
    Task { @MainActor in
      await session.newNote()
      focusTrigger.pulse()
    }
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
      font: editorFont,
      focusRequest: focusTrigger.tick,
      caretEndRequest: focusTrigger.caretEndTick,
      maxVisibleLines: preferences.maxVisibleLines,
      extraChromeHeight: extraChromeHeight,
      findHighlight: find.currentMatch,
      vimModeEnabled: preferences.vimMode,
      vimController: vimController,
      onEscape: { handleEscape() },
      onSendLinearTask: onSendLinearTask,
      onAppendDailyNote: onAppendDailyNote,
      onAppendTrayNote: onAppendTrayNote,
      onAppendStateNote: onAppendStateNote,
      onHeightChange: onHeightChange
    )
    .padding(.leading, EditorMetrics.leadingInset)
    .padding(.trailing, EditorMetrics.trailingInset)
    .padding(.top, EditorMetrics.topInset)
    .padding(.bottom, EditorMetrics.bottomInset)
  }

  private var editorPlaceholder: String {
    switch session.currentVaultState {
    case .tasks: return "Add a task…"
    case nil: return "Jot something down…"
    }
  }

}

// MARK: - Floating modal layer

extension SpotlightRootView {
  private var anyModalShown: Bool {
    fuzzy.isVisible || actionsModalShown || themePickerShown
  }

  /// Transparent tap-catch over the note while a modal shows -- Raycast
  /// leaves the editor UNDIMMED with a menu open (window probes (40,42,56)
  /// either way, 2026-08-09); a click on the note body just dismisses. The
  /// modal sheet itself lives in an overhanging CHILD WINDOW
  /// (`RaycastModalOverhang`) so it can extend past the panel's bottom
  /// edge like the live app; neither layer ever touches the measured
  /// height tree.
  @ViewBuilder
  private var modalLayer: some View {
    if anyModalShown {
      surfaceShape
        .fill(Color.clear)
        .contentShape(surfaceShape)
        .onTapGesture { dismissModals() }
    }
  }

  @ViewBuilder
  private var activeModal: some View {
    if fuzzy.isVisible {
      RaycastNotesModal(
        controller: fuzzy,
        currentChatID: session.currentID,
        isDeletable: { session.isDeletable($0) },
        onPick: { chat in
          session.jump(to: chat)
        },
        onTogglePin: { chat in
          Task { @MainActor in
            await session.togglePin(chat)
          }
        },
        onDelete: { chat in
          Task { @MainActor in
            await session.delete(chat)
            fuzzy.updateCorpus(session.chats)
          }
        }
      )
    } else if actionsModalShown {
      RaycastActionsModal(actions: modalActions, onClose: { actionsModalShown = false })
    } else {
      RaycastThemesModal(preferences: preferences, onClose: { themePickerShown = false })
    }
  }

  private var modalActions: [RaycastAction] {
    // Raycast's live row order: note actions, then find/copy, then chrome.
    let currentChat = session.chats.first(where: { $0.id == session.currentID })
    let currentPinned = currentChat?.isPinned ?? false
    return [
      RaycastAction(
        id: "new-note",
        title: "New Note",
        icon: .raster(resource: "RaycastPlus", frame: 19.5),
        keys: keycaps(for: .newNote),
        section: 0,
        // Frames re-pinned round 12: the live rows' icon ink runs 34px
        // at 2x (ours drew 31 at 17.5pt frames) -- 19.5pt with the
        // 0.875-ink rasters lands 34.1; the Plus and TextSearch carry
        // their own ink ratios.
        // Raycast dims New Note while the current note is empty -- the
        // new note would be an identical blank.
        isEnabled: !session.currentText.isEmpty,
        perform: { newNote() }
      ),
      RaycastAction(
        id: "duplicate-note",
        title: "Duplicate Note",
        icon: .raster(resource: "RaycastDuplicate", frame: 19.5),
        keys: keycaps(for: .duplicateNote),
        section: 0,
        // Raycast dims Duplicate on an empty note -- nothing to copy.
        isEnabled: !session.currentText.isEmpty,
        perform: { Task { @MainActor in await session.duplicateCurrent() } }
      ),
      RaycastAction(
        id: "pin-note",
        title: currentPinned ? "Unpin Note" : "Pin Note",
        icon: .raster(resource: "RaycastTack", frame: 19.5),
        keys: keycaps(for: .togglePin),
        section: 0,
        // Vault-backed notes live outside the store and cannot pin.
        isEnabled: currentChat.map { session.isDeletable($0) } ?? false,
        perform: {
          guard let chat = currentChat else { return }
          Task { @MainActor in await session.togglePin(chat) }
        }
      ),
      RaycastAction(
        id: "browse-notes",
        title: "Browse Notes",
        icon: .stackedCards,
        keys: keycaps(for: .browseNotes),
        section: 0,
        perform: { fuzzy.toggle(corpus: session.chats) }
      ),
      RaycastAction(
        id: "go-back",
        title: "Go Back",
        icon: .raster(resource: "RaycastArrowLeftCircle", frame: 19.5),
        keys: keycaps(for: .goBack),
        section: 0,
        isEnabled: session.canGoBack,
        perform: { Task { @MainActor in await session.goBack() } }
      ),
      RaycastAction(
        id: "go-forward",
        title: "Go Forward",
        icon: .raster(resource: "RaycastArrowRightCircle", frame: 19.5),
        keys: keycaps(for: .goForward),
        section: 0,
        isEnabled: session.canGoForward,
        perform: { Task { @MainActor in await session.goForward() } }
      ),
      RaycastAction(
        id: "find-in-note",
        title: "Find in Note",
        // Raycast's Find glyph is text lines + magnifier; not in the
        // public @raycast/icons set, so the SVG (in Resources, beside
        // its raster) is composed from David's capture geometry.
        icon: .raster(resource: "RaycastTextSearch", frame: 20),
        keys: keycaps(for: .findInNote),
        section: 1,
        // Inapplicable on an empty note: dims like the live menu's
        // greyed rows instead of offering a no-op.
        isEnabled: !session.currentText.isEmpty,
        perform: { find.toggle(text: session.currentText) }
      ),
      RaycastAction(
        id: "copy-note",
        title: "Copy Note",
        icon: .raster(resource: "RaycastCopyClipboard", frame: 19.5),
        keys: keycaps(for: .copyContent),
        section: 1,
        isEnabled: !session.currentText.isEmpty,
        perform: {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(session.currentText, forType: .string)
        }
      ),
      RaycastAction(
        id: "change-theme",
        title: "Change Theme",
        icon: .raster(resource: "RaycastSwatch", frame: 19.5),
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

  private func dismissModals() {
    if fuzzy.isVisible { fuzzy.close() }
    actionsModalShown = false
    themePickerShown = false
  }

  /// Esc closes an open modal before it can close the HUD, so a stray
  /// escape in the themes modal (which has no focused field of its own)
  /// never dismisses the whole panel.
  private func handleEscape() {
    if anyModalShown {
      dismissModals()
    } else {
      onEscape()
    }
  }
}
