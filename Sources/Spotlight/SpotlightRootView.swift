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
  func pulseCaretEnd() { caretEndTick &+= 1 }
}

struct SpotlightRootView: View {
  @ObservedObject var focusTrigger: FocusTrigger
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

  private var extraChromeHeight: CGFloat {
    var total: CGFloat = EditorMetrics.toolbarHeight + EditorMetrics.composerHeight
    if find.isVisible { total += EditorMetrics.findBarHeight }
    if fuzzy.isVisible {
      total += FuzzyPalette.reservedHeight
    }
    return total
  }

  var body: some View {
    VStack(spacing: 0) {
      if find.isVisible {
        FindBar(controller: find, theme: theme, editorText: session.currentText)
          .transition(.opacity)
      }
      editorCard
        .transaction { $0.animation = nil }
      if fuzzy.isVisible {
        FuzzyPalette(controller: fuzzy, theme: theme) { chat in
          session.jump(to: chat)
        }
        .padding(.horizontal, EditorMetrics.outerPadding)
        .padding(.bottom, EditorMetrics.outerPadding)
        .frame(height: FuzzyPalette.reservedHeight)
        .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .colorScheme(theme.mode == .dark ? .dark : .light)
    .animation(.easeOut(duration: 0.10), value: find.isVisible)
    .animation(.easeOut(duration: 0.10), value: fuzzy.isVisible)
    .onChange(of: session.chats) { _, updatedChats in
      fuzzy.updateCorpus(updatedChats)
    }
    .onChange(of: find.isVisible) { _, isVisible in
      if !isVisible { focusTrigger.pulse() }
    }
    .onChange(of: fuzzy.isVisible) { _, isVisible in
      if !isVisible { focusTrigger.pulse() }
    }
    .onAppear {
      let editorHeight = EditorMetrics.panelHeight(
        forLines: EditorMetrics.lineCount(in: session.currentText),
        maxLines: preferences.maxVisibleLines
      )
      onHeightChange(editorHeight + extraChromeHeight)
    }
  }

  private var hasAttachedBottom: Bool {
    fuzzy.isVisible
  }

  // Near-opaque tint over the Liquid Glass surface: the panel should read as a
  // solid card with only a hint of lensing at the edges, not a see-through pane.
  static let darkGlassTintOpacity = 0.90
  static let lightGlassTintOpacity = 0.90

  private var glassTintOpacity: Double {
    theme.mode == .dark ? Self.darkGlassTintOpacity : Self.lightGlassTintOpacity
  }

  private var editorCardShape: UnevenRoundedRectangle {
    let flat = hasAttachedBottom
    return UnevenRoundedRectangle(
      topLeadingRadius: 19,
      bottomLeadingRadius: flat ? 0 : 19,
      bottomTrailingRadius: flat ? 0 : 19,
      topTrailingRadius: 19,
      style: .continuous
    )
  }

  private var editorCard: some View {
    VStack(spacing: 0) {
      GlassToolbar(
        theme: theme,
        isPinned: !preferences.dimOnFocusLoss,
        showsLineNumbers: preferences.showLineNumbers,
        onClose: onEscape,
        onOpenNotes: { fuzzy.toggle(corpus: session.chats) },
        onTogglePin: { preferences.dimOnFocusLoss.toggle() },
        onCycleTheme: cycleTheme,
        onInsertBullet: { appendBulletLine() },
        onToggleLineNumbers: { preferences.showLineNumbers.toggle() },
        onToggleFind: { find.toggle(text: session.currentText) }
      )
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
      ComposerBar(theme: theme) { appendBulletLine($0) }
    }
    .glassEffect(
      .regular.tint(theme.background.opacity(glassTintOpacity)),
      in: editorCardShape
    )
    .overlay(editorCardShape.strokeBorder(theme.border, lineWidth: 1))
    .padding(.top, EditorMetrics.outerPadding)
    .padding(.horizontal, EditorMetrics.outerPadding)
    .padding(.bottom, hasAttachedBottom ? 0 : EditorMetrics.outerPadding)
  }

  private func cycleTheme() {
    let themes = ThemeCatalog.all
    guard !themes.isEmpty else { return }
    let index = themes.firstIndex { $0.id == preferences.selectedThemeID } ?? -1
    preferences.selectedThemeID = themes[(index + 1) % themes.count].id
  }

  /// Appends a fresh `- ` bullet line (optionally pre-filled) and moves the
  /// caret to its end.
  private func appendBulletLine(_ content: String = "") {
    var text = session.currentText
    if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
    text += "- " + content
    session.currentText = text
    session.persistIfNeeded()
    focusTrigger.pulseCaretEnd()
  }

  private var editorPlaceholder: String {
    switch session.currentVaultState {
    case .tasks: return "Add a task…"
    case nil: return "Jot something down…"
    }
  }

}
