// swiftlint:disable file_length type_body_length function_body_length
// swiftlint:disable cyclomatic_complexity
import AppKit
import Combine
import Core
import SwiftUI

@MainActor
public final class SpotlightWindowController {
  nonisolated static let panelStyleMask: NSWindow.StyleMask = [
    .borderless, .fullSizeContentView
  ]
  /// `.screenSaver` keeps the HUD above the window layers used by
  /// fullscreen apps. Lower levels such as `.floating` and `.statusBar`
  /// can still be occluded by fullscreen windows on recent macOS
  /// releases even when the panel joins that Space.
  nonisolated static let panelLevel: NSWindow.Level = .screenSaver
  /// `.canJoinAllApplications` is the cross-app fullscreen guard:
  /// without it, the HUD can activate while the fullscreen app visibly
  /// blurs/refocuses, but the panel is not admitted into that app's
  /// fullscreen Space.
  /// `.canJoinAllSpaces` keeps the panel reachable from every Space,
  /// `.fullScreenAuxiliary` lets it sit alongside fullscreen windows,
  /// `.transient` keeps it in the floating Spaces group. `.stationary`
  /// looks tempting for all-space overlays, but AppKit treats it like
  /// desktop chrome; fullscreen Spaces can then leave a reused panel
  /// behind the fullscreen layer.
  /// `.ignoresCycle` keeps this transient HUD out of Cmd-` cycling.
  nonisolated static let panelCollectionBehavior: NSWindow.CollectionBehavior = [
    .canJoinAllApplications, .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle
  ]
  nonisolated static let defaultUnfocusedAlpha: CGFloat = 0.55
  /// Gap kept between the panel and the screen's right and bottom edges at rest.
  nonisolated static let defaultEdgeInset: CGFloat = 8

  /// X origin: the panel hugs the right edge of the visible frame, inset by
  /// `defaultEdgeInset` (clamped on-screen for narrow displays).
  nonisolated static func restingOriginX(in screenFrame: NSRect, panelWidth: CGFloat) -> CGFloat {
    let rightmostX = max(screenFrame.minX, screenFrame.maxX - panelWidth)
    return min(max(rightmostX - defaultEdgeInset, screenFrame.minX), rightmostX).rounded()
  }

  /// Y origin (the panel's *bottom* edge): the panel hugs the bottom of the
  /// visible frame, inset by `defaultEdgeInset`. The panel is bottom-anchored and
  /// grows upward, so the bottom-right corner stays put as content reflows.
  /// Clamped so a very tall panel never runs off the top of the screen.
  nonisolated static func restingOriginY(in screenFrame: NSRect, panelHeight: CGFloat) -> CGFloat {
    let highestY = max(screenFrame.minY, screenFrame.maxY - panelHeight)
    return min(screenFrame.minY + defaultEdgeInset, highestY).rounded()
  }

  private var panel: SpotlightPanel?
  private var fuzzyPreviewPanel: FuzzyPreviewPanel?
  private var toastPanel: HermesToastPanel?
  private let focusTrigger = FocusTrigger()
  let preferences: ThemePreferences
  let session: ChatSession
  private let shortcuts: ShortcutStore
  let findController = FindController()
  private let fuzzyController = FuzzyController()
  private let copyController = CopyController()
  private let handoffClient = ScratchpadHandoffClient()
  private let dailyNoteWriter = DailyNoteWriter()
  private let trayNoteWriter = TrayNoteWriter()
  private let stateNoteWriter = StateNoteWriter()
  let vimController = VimController()
  private let onOpenSettings: () -> Void
  private let onWillShowHUD: () -> Void
  private let onDidHideHUD: () -> Void
  private var observers: [NSObjectProtocol] = []
  private weak var previouslyActiveApp: NSRunningApplication?
  /// Screen-space Y of the panel's pinned *bottom* edge (the rest origin),
  /// cached on first placement and reused thereafter so the bottom-right corner
  /// stays put and the panel doesn't "jump" between reshows.
  private var pinnedBottomY: CGFloat?
  /// Drives `setPanelHeight`. The HUD is bottom-anchored at the bottom-right
  /// corner, so the rest state is `.bottomPinned(pinnedBottomY)`: the panel's
  /// bottom edge stays fixed and content (editor + navigation overlay) grows
  /// upward as line counts change. The `.none`/`.pendingFirstResize` cases are
  /// retained for the solver's API but are no longer entered by the controller.
  private enum NavAnchorState {
    case none
    case pendingFirstResize
    case bottomPinned(CGFloat)

    var solverAnchor: HUDFrameSolver.NavAnchor {
      switch self {
      case .none: return .none
      case .pendingFirstResize: return .pendingFirstResize
      case .bottomPinned(let y): return .bottomPinned(y: y)
      }
    }
  }
  private enum FuzzyPreviewSide {
    case left
    case right
  }
  private var navAnchor: NavAnchorState = .none
  private struct MeasuredHeightCache {
    let text: String
    let maxVisibleLines: Int
    let chromeAbove: CGFloat
    let chromeBelow: CGFloat
    let height: CGFloat
  }

  /// Screen-space `y` of the editor card's top edge. Every non-nav
  /// resize (tutorial toggle, editor text growth) keeps this point
  /// fixed so the editor never visually jumps. Reset to nil on every
  /// nav-exit and on `focusOrShow` so the next `setPanelHeight`
  /// re-derives it from the freshly-pinned screen position -- that's
  /// what snaps the drifted-during-cycling editor back to its rest
  /// position the moment the user starts typing again.
  private var editorTopY: CGFloat?
  private var measuredHeightCache: MeasuredHeightCache?
  private var programmaticFrameToIgnore: NSRect?
  private var cancellables: Set<AnyCancellable> = []

  /// Layout above the editor card inside the panel (find bar when visible).
  /// Used to map between `panel.top` and `editorTopY`.
  private var chromeAboveEditor: CGFloat {
    var height: CGFloat = 0
    if findController.isVisible { height += EditorMetrics.findBarHeight }
    return height
  }

  /// Layout below the editor card inside the panel -- fuzzy palette or
  /// nav overlay, mutually exclusive. Used by `focusOrShow` to predict
  /// SwiftUI's panel height before activating.
  private var chromeBelowEditor: CGFloat {
    var height: CGFloat = 0
    if fuzzyController.isVisible {
      height += FuzzyPalette.reservedHeight
    }
    return height
  }

  /// Total panel height SwiftUI will render with the current state.
  /// Mirrors `SpotlightRootView.extraChromeHeight + editor`.
  private var expectedPanelHeight: CGFloat {
    let chromeAbove = chromeAboveEditor
    let chromeBelow = chromeBelowEditor
    if let measuredHeightCache {
      if hasMeasuredHeight(forChromeAbove: chromeAbove, chromeBelow: chromeBelow) {
        return measuredHeightCache.height
      }
    }
    let lines = EditorMetrics.lineCount(in: session.currentText)
    let editor = EditorMetrics.panelHeight(forLines: lines, maxLines: preferences.maxVisibleLines)
    return editor + chromeAbove + chromeBelow
  }

  private func hasMeasuredHeight(forChromeAbove chromeAbove: CGFloat, chromeBelow: CGFloat) -> Bool {
    guard let measuredHeightCache else { return false }
    return measuredHeightCache.text == session.currentText
      && measuredHeightCache.maxVisibleLines == preferences.maxVisibleLines
      && measuredHeightCache.chromeAbove == chromeAbove
      && measuredHeightCache.chromeBelow == chromeBelow
  }

  public init(
    preferences: ThemePreferences,
    store: ChatStore,
    shortcuts: ShortcutStore,
    vaultDocuments: [VaultNoteDocument]? = nil,
    onOpenSettings: @escaping () -> Void,
    onWillShowHUD: @escaping () -> Void = {},
    onDidHideHUD: @escaping () -> Void = {}
  ) {
    self.preferences = preferences
    self.session = ChatSession(store: store, vaultDocuments: vaultDocuments)
    self.shortcuts = shortcuts
    self.onOpenSettings = onOpenSettings
    self.onWillShowHUD = onWillShowHUD
    self.onDidHideHUD = onDidHideHUD
    FontLoader.registerBundledFonts()
    observeActiveApp()
    observeFuzzyPreview()
    observeToastMessages()
    installVimCommandRunner()
    Task { [session] in await session.bootstrap() }
  }

  private func observeFuzzyPreview() {
    fuzzyController.$isVisible
      .combineLatest(fuzzyController.$results, fuzzyController.$selectedIndex)
      .sink { [weak self] _, _, _ in
        MainActor.assumeIsolated { self?.syncFuzzyPreviewPanel() }
      }
      .store(in: &cancellables)
  }

  private func syncFuzzyPreviewPanel() {
    guard
      fuzzyController.isVisible,
      fuzzyController.selectedResult() != nil,
      let panel,
      panel.isVisible,
      let frame = fuzzyPreviewFrame(for: panel)
    else {
      fuzzyPreviewPanel?.orderOut(nil)
      return
    }
    let preview = fuzzyPreviewPanel ?? makeFuzzyPreviewPanel(parent: panel)
    fuzzyPreviewPanel = preview
    if preview.parent !== panel {
      panel.addChildWindow(preview, ordered: .above)
    }
    if !Self.rect(preview.frame, isApproximatelyEqualTo: frame) {
      preview.setFrame(frame, display: true)
    }
    if !preview.isVisible {
      preview.orderFrontRegardless()
    }
  }

  private func observeToastMessages() {
    vimController.$message
      .sink { [weak self] message in
        MainActor.assumeIsolated { self?.syncToastPanel(message: message) }
      }
      .store(in: &cancellables)
  }

  private func syncToastPanel(message: VimController.Message? = nil) {
    guard let message = message ?? vimController.message,
      let panel,
      panel.isVisible
    else {
      toastPanel?.orderOut(nil)
      return
    }
    let toast = toastPanel ?? makeToastPanel(parent: panel)
    toastPanel = toast
    if toast.parent !== panel {
      panel.addChildWindow(toast, ordered: .above)
    }
    let content = NSHostingView(
      rootView: HermesToastView(message: message, theme: preferences.activeTheme)
    )
    let size = content.fittingSize
    content.frame = NSRect(origin: .zero, size: size)
    toast.contentView = content
    let frame = toastFrame(for: panel, size: size)
    if !Self.rect(toast.frame, isApproximatelyEqualTo: frame) {
      toast.setFrame(frame, display: true)
    }
    if !toast.isVisible {
      toast.orderFrontRegardless()
    }
  }

  private func makeToastPanel(parent: NSPanel) -> HermesToastPanel {
    let toast = HermesToastPanel(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: Self.panelStyleMask,
      backing: .buffered,
      defer: false
    )
    Self.configurePanel(toast)
    toast.hasShadow = false
    toast.ignoresMouseEvents = true
    parent.addChildWindow(toast, ordered: .above)
    return toast
  }

  private func toastFrame(for panel: NSPanel, size: NSSize) -> NSRect {
    let panelFrame = panel.frame
    let width = ceil(size.width)
    let height = ceil(size.height)
    let topInset = EditorMetrics.outerPadding + 7
    let trailingInset = EditorMetrics.outerPadding + 8
    return NSRect(
      x: (panelFrame.maxX - trailingInset - width).rounded(),
      y: (panelFrame.maxY - topInset - height).rounded(),
      width: width,
      height: height
    )
  }

  private func fuzzyPreviewFrame(for panel: NSPanel) -> NSRect? {
    let screenFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
    guard let screenFrame else { return nil }
    let panelFrame = panel.frame
    let gap = FuzzyPreviewCard.gap
    let rightSpace = screenFrame.maxX - panelFrame.maxX - gap
    let leftSpace = panelFrame.minX - screenFrame.minX - gap
    let preferred = FuzzyPreviewCard.preferredWidth
    let minimum = FuzzyPreviewCard.minimumWidth
    let side: FuzzyPreviewSide
    let width: CGFloat
    if rightSpace >= preferred {
      side = .right
      width = preferred
    } else if leftSpace >= preferred {
      side = .left
      width = preferred
    } else if rightSpace >= leftSpace, rightSpace >= minimum {
      side = .right
      width = rightSpace
    } else if leftSpace >= minimum {
      side = .left
      width = leftSpace
    } else {
      return nil
    }
    let height = min(panelFrame.height, screenFrame.height)
    let y = min(panelFrame.maxY, screenFrame.maxY) - height
    let x: CGFloat
    switch side {
    case .right: x = panelFrame.maxX + gap
    case .left: x = panelFrame.minX - gap - width
    }
    return NSRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
  }

  public func handleHotkey() {
    handleVaultHotkey(.tasks)
  }

  private func handleVaultHotkey(_ state: VaultNoteState) {
    if let panel, panel.isVisible, panel.isKeyWindow, NSApp.isActive, session.currentVaultState == state {
      close()
    } else {
      openVaultState(state)
    }
  }

  public func openHUD() {
    openVaultState(.tasks)
  }

  private func openVaultState(_ state: VaultNoteState) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.session.switchVaultState(state)
      self.focusOrShow()
    }
  }

  /// Summons the Tasks note with the caret
  /// already at the end. Bound to the `appendToLastNote` global chord
  /// (default ⌘⇧.).
  public func handleAppendToLastNote() {
    openVaultState(.tasks)
    // Defer the caret bump one runloop tick so SwiftUI has a chance to
    // propagate the Tasks note into the NSTextView before we ask
    // for end-of-text.
    DispatchQueue.main.async { [weak self] in
      self?.focusTrigger.requestCaretEnd()
    }
  }

  public func reloadLibrary() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.session.reload()
      self.fuzzyController.updateCorpus(self.session.chats)
    }
  }

  /// Awaits every pending debounced write across the chat store *and* the
  /// vault-backed documents (the `## To Do` inbox). Call on app termination
  /// so a last edit isn't lost -- flushing the chat store alone is not enough.
  public func flush() async {
    await session.flush()
  }

  public func close() {
    fuzzyPreviewPanel?.orderOut(nil)
    toastPanel?.orderOut(nil)
    panel?.orderOut(nil)
    // If a bona-fide SpotNote window (Settings) is visible, leave the
    // app active so the user can keep working there. Filter to
    // `canBecomeMain` windows -- the panel itself, SwiftUI hosting
    // scratch windows, and AppKit's internal helper windows all report
    // `canBecomeMain == false`, which caused the previous
    // `$0.isVisible`-only check to spuriously retain focus and break
    // the Terminal -> HUD -> Terminal toggle.
    let hasVisibleMainWindow = NSApp.windows.contains { window in
      window !== panel && window.isVisible && window.canBecomeMain
    }
    if hasVisibleMainWindow { return }
    let target = previouslyActiveApp
    previouslyActiveApp = nil
    NSApp.hide(nil)
    onDidHideHUD()
    if let target, target.bundleIdentifier != Bundle.main.bundleIdentifier {
      target.activate()
    }
  }

  private func focusOrShow() {
    onWillShowHUD()
    let panel = panel ?? makePanel()
    self.panel = panel
    if !NSApp.isActive {
      previouslyActiveApp = NSWorkspace.shared.frontmostApplication
    }
    if !panel.isVisible {
      editorTopY = nil
      repositionForShow(panel)
    }
    panel.alphaValue = 1.0
    NSApp.activate(ignoringOtherApps: true)
    bringPanelToFront(panel)
    focusTrigger.pulse()
  }

  private func bringPanelToFront(_ panel: NSPanel) {
    Self.configurePanel(panel)
    panel.orderFrontRegardless()
    panel.makeKeyAndOrderFront(nil)
    panel.orderFrontRegardless()
    syncFuzzyPreviewPanel()
    syncToastPanel()
  }

  private func repositionForShow(_ panel: NSPanel) {
    guard let screen = NSScreen.main else { return }
    let screenFrame = screen.visibleFrame
    let height = expectedPanelHeight
    let bottom: CGFloat
    if let cached = pinnedBottomY {
      bottom = cached
    } else {
      bottom = Self.restingOriginY(in: screenFrame, panelHeight: height)
      pinnedBottomY = bottom
    }
    let x = Self.restingOriginX(in: screenFrame, panelWidth: panel.frame.width)
    // Bottom-anchored at the bottom-right corner: the origin (bottom edge) is
    // fixed and the panel grows upward as content reflows.
    navAnchor = .bottomPinned(bottom)
    setPanelFrame(
      NSRect(x: x, y: bottom, width: panel.frame.width, height: height),
      display: false
    )
  }

  private func makePanel() -> SpotlightPanel {
    let initialHeight = EditorMetrics.panelHeight(
      forLines: 1,
      maxLines: preferences.maxVisibleLines
    )
    let size = NSSize(width: EditorMetrics.panelWidth, height: initialHeight)
    let panel = SpotlightPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: Self.panelStyleMask,
      backing: .buffered,
      defer: false
    )
    Self.configurePanel(panel)
    panel.contentView = NSHostingView(
      rootView: SpotlightRootView(
        focusTrigger: focusTrigger,
        preferences: preferences,
        session: session,
        shortcuts: shortcuts,
        find: findController,
        fuzzy: fuzzyController,
        vimController: vimController,
        onHeightChange: { [weak self] height in
          self?.setPanelHeight(height, animated: false)
        },
        onEscape: { [weak self] in
          self?.close()
        },
        onSendLinearTask: { [handoffClient] request in
          try await handoffClient.sendLinearTask(request)
        },
        onAppendDailyNote: { [dailyNoteWriter] text in
          try await dailyNoteWriter.append(text)
        },
        onAppendTrayNote: { [trayNoteWriter] text in
          try await trayNoteWriter.append(text)
        },
        onAppendStateNote: { [stateNoteWriter] text in
          try await stateNoteWriter.append(text)
        }
      )
    )
    panel.keyEquivalentHandler = { [weak self] event in
      self?.handleKeyEquivalent(event) ?? false
    }
    observeKeyState(panel)
    return panel
  }

  static func configurePanel(_ panel: NSPanel) {
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isFloatingPanel = true
    panel.level = panelLevel
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.isMovableByWindowBackground = true
    panel.collectionBehavior = panelCollectionBehavior
  }

  private func makeFuzzyPreviewPanel(parent: NSPanel) -> FuzzyPreviewPanel {
    let preview = FuzzyPreviewPanel(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: FuzzyPreviewCard.preferredWidth,
        height: max(parent.frame.height, FuzzyPalette.reservedHeight)
      ),
      styleMask: Self.panelStyleMask,
      backing: .buffered,
      defer: false
    )
    Self.configurePanel(preview)
    preview.hasShadow = false
    preview.ignoresMouseEvents = false
    preview.contentView = NSHostingView(
      rootView: FuzzyPreviewCard(
        controller: fuzzyController,
        preferences: preferences
      )
    )
    parent.addChildWindow(preview, ordered: .above)
    return preview
  }

  private static let driftCorrectionThreshold: CGFloat = 4

  private func pinnedOrigin(for panel: NSPanel) -> NSPoint? {
    guard let screen = NSScreen.main else { return nil }
    let screenFrame = screen.visibleFrame
    let bottom: CGFloat
    if let cached = pinnedBottomY {
      bottom = cached
    } else {
      let initialHeight = EditorMetrics.panelHeight(
        forLines: 1,
        maxLines: preferences.maxVisibleLines
      )
      bottom = Self.restingOriginY(in: screenFrame, panelHeight: initialHeight)
      pinnedBottomY = bottom
    }
    let x = Self.restingOriginX(in: screenFrame, panelWidth: panel.frame.width)
    return NSPoint(x: x, y: bottom)
  }

  private func correctDriftIfNeeded(_ panel: NSPanel) {
    guard let target = pinnedOrigin(for: panel) else { return }
    let current = panel.frame.origin
    let dx = abs(current.x - target.x)
    let dy = abs(current.y - target.y)
    guard dx > 0 || dy > 0 else { return }
    guard dx <= Self.driftCorrectionThreshold, dy <= Self.driftCorrectionThreshold else {
      return
    }
    setPanelFrame(
      NSRect(origin: target, size: panel.frame.size),
      display: true
    )
  }

  private func setPanelHeight(_ height: CGFloat, animated: Bool) {
    guard let panel else { return }
    let current = panel.frame
    let chromeAbove = chromeAboveEditor
    let resolved = HUDFrameSolver.resolveNewY(
      anchor: navAnchor.solverAnchor,
      currentOriginY: current.origin.y,
      currentHeight: current.size.height,
      newHeight: height,
      chromeAbove: chromeAbove,
      cachedEditorTopY: editorTopY,
      pinnedTopY: pinnedBottomY
    )
    let newY = resolved.newOriginY
    if let updated = resolved.editorTopY { editorTopY = updated }
    let newFrame = NSRect(
      x: current.origin.x,
      y: newY,
      width: current.size.width,
      height: height
    )
    measuredHeightCache = MeasuredHeightCache(
      text: session.currentText,
      maxVisibleLines: preferences.maxVisibleLines,
      chromeAbove: chromeAbove,
      chromeBelow: chromeBelowEditor,
      height: height
    )
    setPanelFrame(newFrame, display: true, animate: animated)
    if case .pendingFirstResize = navAnchor {
      // The overlay is now on screen. Lock its bottom edge for every
      // subsequent cycle.
      navAnchor = .bottomPinned(newY)
    }
  }

  private func setPanelFrame(_ frame: NSRect, display: Bool, animate: Bool = false) {
    guard let panel else { return }
    programmaticFrameToIgnore = frame
    panel.setFrame(frame, display: display, animate: animate)
    syncFuzzyPreviewPanel()
    syncToastPanel()
  }

  private func shouldIgnoreProgrammaticMove(_ frame: NSRect) -> Bool {
    guard let expected = programmaticFrameToIgnore else { return false }
    guard Self.rect(frame, isApproximatelyEqualTo: expected) else { return false }
    programmaticFrameToIgnore = nil
    return true
  }

  private static func rect(_ lhs: NSRect, isApproximatelyEqualTo rhs: NSRect) -> Bool {
    let tolerance: CGFloat = 0.5
    return abs(lhs.origin.x - rhs.origin.x) <= tolerance
      && abs(lhs.origin.y - rhs.origin.y) <= tolerance
      && abs(lhs.size.width - rhs.size.width) <= tolerance
      && abs(lhs.size.height - rhs.size.height) <= tolerance
  }

}

extension SpotlightWindowController {
  private func observeKeyState(_ panel: SpotlightPanel) {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: panel,
        queue: .main
      ) { [weak self, weak panel] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          if self.preferences.dimOnFocusLoss {
            panel?.animator().alphaValue = CGFloat(self.preferences.unfocusedOpacity)
          } else {
            self.close()
          }
        }
      }
    )
    observers.append(
      center.addObserver(
        forName: NSWindow.didBecomeKeyNotification,
        object: panel,
        queue: .main
      ) { [weak self, weak panel] _ in
        MainActor.assumeIsolated {
          panel?.animator().alphaValue = 1.0
          if let self, let panel { self.correctDriftIfNeeded(panel) }
        }
      }
    )
    observers.append(
      center.addObserver(
        forName: NSWindow.didMoveNotification,
        object: panel,
        queue: .main
      ) { [weak self, weak panel] _ in
        MainActor.assumeIsolated {
          guard let self, let panel else { return }
          if self.shouldIgnoreProgrammaticMove(panel.frame) { return }
          let newBottom = panel.frame.origin.y
          self.pinnedBottomY = newBottom
          self.navAnchor = .bottomPinned(newBottom)
          self.syncFuzzyPreviewPanel()
          self.syncToastPanel()
        }
      }
    )
  }
  /// Called from `SpotlightPanel.performKeyEquivalent(with:)` so every
  /// chord in the HUD -- settings, handoff, copy, and editor helpers --
  /// flows through a single user-customizable binding table
  /// AND participates in AppKit's key-equivalent responder chain.
  /// Returning `true` tells macOS the event was consumed (no beep).
  ///
  private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
    // #lizard forgives
    let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    let mods = ShortcutModifierSet(event.modifierFlags.intersection(mask))
    let chars = Shortcut.normalize(event.charactersIgnoringModifiers ?? "")
    let resolved = MainActor.assumeIsolated { shortcuts.match(key: chars, modifiers: mods) }
    guard let action = resolved else { return false }
    if action == .toggleHotkey || action == .appendToLastNote { return false }
    if !shouldHandle(action: action) {
      if action == .copyContent {
        MainActor.assumeIsolated {
          _ = panel?.firstResponder?.tryToPerform(#selector(NSText.copy(_:)), with: nil)
        }
        return true
      }
      return false
    }
    Task { @MainActor [weak self] in self?.dispatch(action) }
    return true
  }

  /// Pass-through gates for context-sensitive shortcuts, such as copy with an active selection.
  private func shouldHandle(action: ShortcutAction) -> Bool {
    if action == .copyContent {
      let hasSelection = MainActor.assumeIsolated {
        (panel?.firstResponder as? NSTextView).map { $0.selectedRange.length > 0 } ?? false
      }
      return !hasSelection
    }
    return true
  }

  // #lizard forgives
  private func dispatch(_ action: ShortcutAction) {
    switch action {
    case .findInNote:
      if fuzzyController.isVisible { fuzzyController.close() }
      findController.toggle(text: session.currentText)
    case .insertTodayBadge:
      _ = panel?.firstResponder?.tryToPerform(
        #selector(PlaceholderTextView.insertTodayBadgeToken(_:)),
        with: nil
      )
    case .sendToLinear:
      _ = panel?.firstResponder?.tryToPerform(
        #selector(PlaceholderTextView.sendCurrentLineToLinearShortcut(_:)),
        with: nil
      )
    case .appendToDailyNote:
      _ = panel?.firstResponder?.tryToPerform(
        #selector(PlaceholderTextView.appendCurrentLineToDailyNoteShortcut(_:)),
        with: nil
      )
    case .copyContent:
      copyController.copy(session.currentText)
    case .openSettings: onOpenSettings()
    case .toggleHotkey, .appendToLastNote: break
    }
  }

  private func observeActiveApp() {
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          let next = NSWorkspace.shared.frontmostApplication
          if next?.bundleIdentifier != Bundle.main.bundleIdentifier {
            self?.previouslyActiveApp = next
          }
        }
      }
    )
  }
}
