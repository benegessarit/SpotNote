import AppKit
import Combine
import SwiftUI

@MainActor
final class FocusTrigger: ObservableObject {
  @Published private(set) var tick: Int = 0
  /// Bumped to ask the editor to move its caret to the very end of the
  /// current note's text. Used by the append-to-last-note global hotkey.
  @Published private(set) var caretEndTick: Int = 0
  func pulse() { tick &+= 1 }
  func requestCaretEnd() { caretEndTick &+= 1 }
}

private enum EditorFont {
  static let preferredNames = [
    "Writer",
    "MonoLisa",
    "MonoLisa-Regular",
    "JetBrains Mono",
    "JetBrainsMono-Regular",
    "JetBrainsMono Nerd Font"
  ]
}

struct SpotlightRootView: View {
  @ObservedObject var focusTrigger: FocusTrigger
  @ObservedObject var preferences: ThemePreferences
  @ObservedObject var session: ChatSession
  @ObservedObject var shortcuts: ShortcutStore
  @ObservedObject var find: FindController
  @ObservedObject var fuzzy: FuzzyController
  @ObservedObject var command: CommandController
  @ObservedObject var vimController: VimController
  /// Called synchronously from the editor delegate when the text's line
  /// count changes, so the panel resize happens in the same runloop tick
  /// as the text mutation (no flash).
  let onHeightChange: (CGFloat) -> Void
  /// Invoked when Esc should dismiss the HUD (vim off, or vim on and
  /// already in normal mode).
  let onEscape: () -> Void

  private var theme: Theme { preferences.activeTheme }

  private var editorFont: NSFont {
    EditorFont.preferredNames
      .lazy
      .compactMap { NSFont(name: $0, size: EditorMetrics.fontSize) }
      .first
      ?? .monospacedSystemFont(ofSize: EditorMetrics.fontSize, weight: .regular)
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

  static let vimBarHeight: CGFloat = 36

  private var extraChromeHeight: CGFloat {
    var total: CGFloat = 0
    if find.isVisible { total += EditorMetrics.findBarHeight }
    if preferences.showHints { total += EditorMetrics.tutorialBarHeight }
    if preferences.vimMode { total += Self.vimBarHeight }
    if fuzzy.isVisible {
      total += FuzzyPalette.reservedHeight
    } else if command.isVisible {
      total += CommandPalette.reservedHeight
    } else if session.navigationPreview != nil {
      total += NavigationOverlay.reservedHeight
    }
    return total
  }

  var body: some View {
    VStack(spacing: 0) {
      if find.isVisible {
        FindBar(controller: find, theme: theme, editorText: session.currentText)
          .transition(.opacity)
      }
      if preferences.showHints {
        TutorialBar(theme: theme, shortcuts: shortcuts) {
          preferences.showHints = false
        }
      }
      editorCard
        .transaction { $0.animation = nil }
      if preferences.vimMode {
        vimModeBar
          .transaction { $0.animation = nil }
      }
      if fuzzy.isVisible {
        FuzzyPalette(controller: fuzzy, theme: theme) { chat in
          session.jump(to: chat)
        }
        .padding(.horizontal, EditorMetrics.outerPadding)
        .padding(.bottom, EditorMetrics.outerPadding)
        .frame(height: FuzzyPalette.reservedHeight)
        .transition(.opacity)
      } else if command.isVisible {
        CommandPalette(controller: command, theme: theme)
          .padding(.horizontal, EditorMetrics.outerPadding)
          .padding(.bottom, EditorMetrics.outerPadding)
          .frame(height: CommandPalette.reservedHeight)
          .transition(.opacity)
      } else if let preview = session.navigationPreview {
        NavigationOverlay(
          preview: preview,
          theme: theme,
          shortcuts: shortcuts,
          canUndo: session.lastDeleted != nil
        )
        .padding(.horizontal, EditorMetrics.outerPadding)
        .padding(.bottom, EditorMetrics.outerPadding)
        .frame(height: NavigationOverlay.reservedHeight)
        .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .colorScheme(theme.mode == .dark ? .dark : .light)
    .animation(.easeOut(duration: 0.10), value: session.navigationPreview != nil)
    .animation(.easeOut(duration: 0.10), value: find.isVisible)
    .animation(.easeOut(duration: 0.10), value: fuzzy.isVisible)
    .animation(.easeOut(duration: 0.10), value: command.isVisible)
    .onChange(of: session.chats) { _, newChats in
      fuzzy.updateCorpus(newChats)
    }
    .onChange(of: find.isVisible) { _, isVisible in
      if !isVisible { focusTrigger.pulse() }
    }
    .onChange(of: fuzzy.isVisible) { _, isVisible in
      if !isVisible { focusTrigger.pulse() }
    }
    .onChange(of: command.isVisible) { _, isVisible in
      if !isVisible { focusTrigger.pulse() }
    }
    .onChange(of: preferences.showHints) { _, _ in
      let editorHeight = EditorMetrics.panelHeight(
        forLines: EditorMetrics.lineCount(in: session.currentText),
        maxLines: preferences.maxVisibleLines
      )
      onHeightChange(editorHeight + extraChromeHeight)
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
    preferences.vimMode || session.navigationPreview != nil
      || fuzzy.isVisible || command.isVisible
  }

  private var editorCardShape: UnevenRoundedRectangle {
    let flat = hasAttachedBottom
    return UnevenRoundedRectangle(
      topLeadingRadius: 10,
      bottomLeadingRadius: flat ? 0 : 10,
      bottomTrailingRadius: flat ? 0 : 10,
      topTrailingRadius: 10,
      style: .continuous
    )
  }

  private var editorCard: some View {
    MultilineEditor(
      text: editorText,
      theme: theme,
      placeholder: "Jot something down…",
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
      onHeightChange: onHeightChange
    )
    .padding(.leading, EditorMetrics.leadingInset)
    .padding(.trailing, EditorMetrics.trailingInset)
    .padding(.vertical, EditorMetrics.verticalInset)
    .background(editorCardShape.fill(theme.background))
    .overlay(editorCardShape.strokeBorder(theme.border, lineWidth: 1))
    .padding(.top, EditorMetrics.outerPadding)
    .padding(.horizontal, EditorMetrics.outerPadding)
    .padding(.bottom, hasAttachedBottom ? 0 : EditorMetrics.outerPadding)
  }

  private var hasOverlayBelow: Bool {
    fuzzy.isVisible || command.isVisible || session.navigationPreview != nil
  }

  private var vimModeBar: some View {
    VimStatusLine(
      theme: theme,
      currentText: session.currentText,
      mode: vimController.mode,
      prompt: vimController.prompt,
      message: vimController.message,
      searchStatus: vimController.searchStatus,
      hasOverlayBelow: hasOverlayBelow,
      height: Self.vimBarHeight
    )
    .padding(.horizontal, EditorMetrics.outerPadding)
  }
}
