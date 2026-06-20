// swiftlint:disable function_body_length
import AppKit
import Combine
import Core
import Spotlight

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private static let headlessTestEnvironmentKey = "SPOTNOTE_HEADLESS_TEST"

  private lazy var preferences = ThemePreferences()
  private lazy var shortcutStore = ShortcutStore()
  private lazy var settings = SettingsWindowController(
    preferences: preferences,
    shortcuts: shortcutStore,
    store: chatStore,
    onLibraryChanged: { [weak self] in self?.handleLibraryChangedFromSettings() }
  )
  private lazy var chatStore: ChatStore = {
    if let store = try? ChatStore(directory: ChatStore.defaultDirectory()) {
      return store
    }
    let fallback = FileManager.default.temporaryDirectory.appending(
      path: "SpotNote-Chats-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    guard let store = try? ChatStore(directory: fallback) else {
      fatalError("ChatStore fallback directory unreachable: \(fallback.path)")
    }
    return store
  }()
  private lazy var spotlight = SpotlightWindowController(
    preferences: preferences,
    store: chatStore,
    shortcuts: shortcutStore,
    vaultDocuments: [
      VaultNoteDocument(state: .tasks)
    ],
    onOpenSettings: { [weak self] in self?.showSettings() },
    onWillShowHUD: {
      DockIconSwitcher.applyVisibility(true)
    },
    onDidHideHUD: { [weak self] in
      self?.applyDockVisibilityWhenIdle()
    }
  )
  private var menuBar: MenuBarController?
  private var hotkey: GlobalHotkey?
  private var appendHotkey: GlobalHotkey?
  private var onboarding: OnboardingController?
  private var cancellables: Set<AnyCancellable> = []

  private var isHeadlessTestLaunch: Bool {
    Self.environmentFlag(Self.headlessTestEnvironmentKey)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    MainMenu.install(onOpenSettings: { [weak self] in self?.showSettings() })
    observeUpdateNotifications()
    if isHeadlessTestLaunch {
      // Agent/CI smoke launches should prove the bundle initializes without
      // stealing focus, opening the HUD, registering global hotkeys, or
      // changing Launch-at-Login state.
      _ = spotlight
      Self.writeHeadlessReadyMarker()
      return
    }
    enableLaunchAtLoginIfFirstRun()
    installGlobalHotkeys()
    DockIconSwitcher.apply(preferences.dockIconStyle)
    // Force the Spotlight controller to initialize so its key monitor is
    // installed before the user presses the toggle chord.
    _ = spotlight
    applyInitialHotkeyBindings()
    observeShortcutBindings()
    observeDockPreferences()
    presentInitialSurface()
  }

  private func observeUpdateNotifications() {
    NotificationCenter.default.addObserver(
      forName: .spotNoteCheckForUpdates,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { UpdateController.shared.checkForUpdates(nil) }
    }
  }

  private func installGlobalHotkeys() {
    hotkey = GlobalHotkey { [weak self] in
      guard let self else { return }
      if let onboarding = self.onboarding, onboarding.isActive {
        onboarding.handleGlobalToggleChord()
        return
      }
      self.spotlight.handleHotkey()
    }
    appendHotkey = GlobalHotkey { [weak self] in
      guard let self else { return }
      if self.onboarding?.isActive == true { return }
      self.spotlight.handleAppendToLastNote()
    }
  }

  private func applyInitialHotkeyBindings() {
    applyToggleHotkey(shortcutStore.binding(for: .toggleHotkey))
    applyAppendHotkey(shortcutStore.binding(for: .appendToLastNote))
  }

  private func observeShortcutBindings() {
    shortcutStore.$bindings
      .map { $0[.toggleHotkey] ?? ShortcutAction.toggleHotkey.defaultShortcut }
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] shortcut in
        MainActor.assumeIsolated { self?.applyToggleHotkey(shortcut) }
      }
      .store(in: &cancellables)

    shortcutStore.$bindings
      .map { $0[.appendToLastNote] ?? ShortcutAction.appendToLastNote.defaultShortcut }
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] shortcut in
        MainActor.assumeIsolated { self?.applyAppendHotkey(shortcut) }
      }
      .store(in: &cancellables)
  }

  private func observeDockPreferences() {
    preferences.$showDockIcon
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] show in
        MainActor.assumeIsolated {
          if show {
            DockIconSwitcher.applyVisibility(true)
            DockIconSwitcher.apply(self?.preferences.dockIconStyle ?? .dark)
          } else {
            self?.applyDockVisibilityWhenIdle()
          }
        }
      }
      .store(in: &cancellables)

    preferences.$dockIconStyle
      .removeDuplicates()
      .dropFirst()
      .sink { style in
        MainActor.assumeIsolated { DockIconSwitcher.apply(style) }
      }
      .store(in: &cancellables)
  }

  private func presentInitialSurface() {
    guard !isHeadlessTestLaunch else { return }
    let didPresentOnboarding = presentOnboardingIfNeeded()
    // SpotNote is a HUD-first app: opening the app should always surface the
    // note window. The previous Apple-event launch-kind check could overfire
    // under LaunchServices and leave a live menu/background process with no
    // visible HUD.
    if !didPresentOnboarding {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.spotlight.openHUD()
        self.installMenuBarIfNeeded()
      }
    } else {
      installMenuBarIfNeeded()
    }
  }

  private func installMenuBarIfNeeded() {
    guard menuBar == nil else { return }
    // Build the status item after requesting the first HUD/onboarding window.
    // Under LaunchServices, letting Control Center host the menu-bar item as
    // the app's first scene can leave SpotNote running but not visible.
    menuBar = MenuBarController(
      preferences: preferences,
      onOpenSettings: { [weak self] in self?.showSettings() }
    )
  }

  private func applyDockVisibilityWhenIdle() {
    guard !preferences.showDockIcon else {
      DockIconSwitcher.applyVisibility(true)
      DockIconSwitcher.apply(preferences.dockIconStyle)
      return
    }
    let hasVisibleWindow = NSApp.windows.contains { window in
      window.isVisible && (window.canBecomeMain || window.canBecomeKey)
    }
    guard !hasVisibleWindow else { return }
    DockIconSwitcher.applyVisibility(false)
  }

  private func presentOnboardingIfNeeded() -> Bool {
    guard !isHeadlessTestLaunch else { return false }
    guard OnboardingController.shouldShow() else { return false }
    let controller = OnboardingController(
      theme: preferences.activeTheme,
      shortcuts: shortcutStore,
      onFinished: { [weak self] _ in
        guard let self else { return }
        self.onboarding = nil
        self.preferences.showHints = true
        self.spotlight.openHUD()
      }
    )
    onboarding = controller
    // Defer one runloop tick so the spotlight controller and menu bar
    // finish their own first-pass setup before the tutorial steals focus.
    DispatchQueue.main.async { [weak controller] in controller?.show() }
    return true
  }

  private func showSettings() {
    settings.show()
  }

  private func handleLibraryChangedFromSettings() {
    spotlight.reloadLibrary()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  // Re-clicking the app icon (Finder, /Applications, Launchpad, dock) on
  // a running instance routes through here. Treat it like the toggle
  // chord so users without the menubar icon visible can still summon
  // the HUD by opening the app. First-run users see onboarding instead.
  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if isHeadlessTestLaunch { return true }
    if OnboardingController.shouldShow() {
      _ = presentOnboardingIfNeeded()
    } else if onboarding?.isActive == true {
      onboarding?.handleGlobalToggleChord()
    } else {
      spotlight.openHUD()
    }
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    let spotlight = self.spotlight
    let semaphore = DispatchSemaphore(value: 0)
    Task {
      // Flush the chat store *and* the vault-backed inbox documents; the
      // vault inbox is owned by the window controller's session, so flushing
      // the chat store alone would drop a final `## To Do` edit on quit.
      await spotlight.flush()
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + .milliseconds(800))
  }

  /// Opt every new install into background autostart so the global
  /// hotkey works after a reboot without any setup. Subsequent launches
  /// respect whatever the user toggles in Settings.
  private func enableLaunchAtLoginIfFirstRun() {
    let key = "launchAtLogin.didInitialize"
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: key) == nil else { return }
    defaults.set(true, forKey: key)
    if LaunchAtLogin.setEnabled(true) {
      preferences.launchAtLogin = true
    }
  }

  private func applyToggleHotkey(_ shortcut: Shortcut) {
    // Fall back to the default if the user somehow configured a key
    // we can't translate into a Carbon virtual code (the recorder
    // should prevent this, but keep the toggle functional regardless).
    if hotkey?.apply(shortcut) == true { return }
    _ = hotkey?.apply(ShortcutAction.toggleHotkey.defaultShortcut)
  }

  private func applyAppendHotkey(_ shortcut: Shortcut) {
    if appendHotkey?.apply(shortcut) == true { return }
    _ = appendHotkey?.apply(ShortcutAction.appendToLastNote.defaultShortcut)
  }

  private static func environmentFlag(_ key: String) -> Bool {
    guard let value = ProcessInfo.processInfo.environment[key] else { return false }
    switch value.lowercased() {
    case "1", "true", "yes", "on": return true
    default: return false
    }
  }

  private static func writeHeadlessReadyMarker() {
    FileHandle.standardError.write(Data("SpotNote headless test launch ready\n".utf8))
  }
}
