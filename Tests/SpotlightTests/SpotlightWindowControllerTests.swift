import AppKit
import Core
import Foundation
import Testing

@testable import Spotlight

@Suite("SpotlightWindowController")
struct SpotlightWindowControllerTests {
  /// **Regression guard** -- SpotNote may hide from the Dock at runtime with
  /// the accessory activation policy, but the panel itself must still be a
  /// regular activating NSPanel. `.nonactivatingPanel` was tried as part of an
  /// over-fullscreen fix and reproduced the no-visible-HUD symptom. The
  /// over-fullscreen path is handled instead by `panelLevel == .screenSaver`,
  /// `.canJoinAllApplications`, and `.fullScreenAuxiliary` in the collection
  /// behavior -- see the dedicated tests below.
  @Test("panel style mask must NOT contain .nonactivatingPanel")
  func panelStyleMaskExcludesNonactivating() {
    #expect(!SpotlightWindowController.panelStyleMask.contains(.nonactivatingPanel))
  }

  @Test("panel style mask is borderless with full-size content")
  func panelStyleMaskShape() {
    let mask = SpotlightWindowController.panelStyleMask
    #expect(mask.contains(.borderless))
    #expect(mask.contains(.fullSizeContentView))
    #expect(!mask.contains(.titled))
    #expect(!mask.contains(.resizable))
    #expect(!mask.contains(.closable))
    #expect(!mask.contains(.miniaturizable))
  }

  /// **Regression guard** -- `.fullScreenAuxiliary` is what allows the
  /// HUD to render in a Space owned by a fullscreen app. Without it,
  /// the panel is hidden behind the fullscreen layer and never shown.
  @Test(
    "panel collection behavior includes .fullScreenAuxiliary -- required for over-fullscreen HUD"
  )
  func panelCollectionBehaviorAllowsFullscreen() {
    let behavior = SpotlightWindowController.panelCollectionBehavior
    #expect(behavior.contains(.fullScreenAuxiliary))
    #expect(behavior.contains(.canJoinAllSpaces))
  }

  /// **Regression guard** -- macOS 13+ fullscreen Spaces are scoped to
  /// application sets. `.canJoinAllSpaces` is not enough for a HUD summoned
  /// over another app; the panel must also be allowed to join other apps'
  /// fullscreen sets.
  @Test("panel can join all applications -- required for cross-app fullscreen HUD")
  func panelCanJoinAllApplications() {
    let behavior = SpotlightWindowController.panelCollectionBehavior
    #expect(behavior.contains(.canJoinAllApplications))
    #expect(!behavior.contains(.primary))
    #expect(!behavior.contains(.auxiliary))
  }

  /// **Regression guard** -- the HUD is a summonable floating overlay,
  /// not desktop chrome. `.stationary` can leave a reused panel behind
  /// a fullscreen window set after AppKit rebuilds Spaces membership.
  @Test("panel uses transient Spaces behavior -- required for reused over-fullscreen HUD")
  func panelUsesTransientSpacesBehavior() {
    let behavior = SpotlightWindowController.panelCollectionBehavior
    #expect(behavior.contains(.transient))
    #expect(!behavior.contains(.managed))
    #expect(!behavior.contains(.stationary))
  }

  /// **Regression guard** -- recent macOS releases can keep
  /// fullscreen windows above `.statusBar` auxiliary panels. The HUD is
  /// transient, so it uses the overlay-grade screen saver level.
  @Test("panel level is .screenSaver -- required for over-fullscreen HUD")
  func panelLevelIsAboveFullscreen() {
    #expect(SpotlightWindowController.panelLevel == .screenSaver)
  }

  @Test("configured panel applies fullscreen overlay behavior")
  @MainActor
  func configuredPanelAppliesFullscreenOverlayBehavior() {
    let panel = SpotlightPanel(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
      styleMask: SpotlightWindowController.panelStyleMask,
      backing: .buffered,
      defer: false
    )

    SpotlightWindowController.configurePanel(panel)

    #expect(panel.level == .screenSaver)
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(panel.collectionBehavior.contains(.transient))
    #expect(!panel.collectionBehavior.contains(.stationary))
    #expect(panel.collectionBehavior.contains(.ignoresCycle))
    #expect(panel.hidesOnDeactivate == false)
    #expect(panel.isFloatingPanel)
  }

  @Test("default unfocused alpha is between 0.5 and 1.0 -- visible but clearly faded")
  func defaultUnfocusedAlphaInRange() {
    let alpha = SpotlightWindowController.defaultUnfocusedAlpha
    #expect(alpha > 0.5)
    #expect(alpha < 1.0)
  }

  @Test("default HUD origin is shifted thirty percent from center toward the right edge")
  func defaultHUDOriginIsShiftedRightOfCenter() {
    let screen = NSRect(x: 0, y: 0, width: 1_000, height: 700)
    let panelWidth: CGFloat = 400
    let centeredX = (screen.midX - panelWidth / 2).rounded()
    let rightmostX = screen.maxX - panelWidth
    let expectedX = (centeredX + (rightmostX - centeredX) * 0.30).rounded()

    let x = SpotlightWindowController.restingOriginX(in: screen, panelWidth: panelWidth)

    #expect(x == expectedX)
    #expect(x > centeredX)
  }

  @Test("default HUD origin stays on-screen after shifting right")
  func defaultHUDOriginDoesNotOverflowRightEdge() {
    let screen = NSRect(x: 100, y: 0, width: 640, height: 700)
    let panelWidth: CGFloat = 620

    let x = SpotlightWindowController.restingOriginX(in: screen, panelWidth: panelWidth)

    #expect(x >= screen.minX)
    #expect(x + panelWidth <= screen.maxX)
  }

  @Test("default HUD origin is vertically centered slightly below the midline")
  func defaultHUDOriginIsSlightlyBelowMidline() {
    let screen = NSRect(x: 0, y: 0, width: 1_000, height: 700)
    let panelHeight: CGFloat = 360
    let expectedCenterY = (screen.midY - screen.height * 0.06).rounded()

    let y = SpotlightWindowController.restingOriginY(in: screen, panelHeight: panelHeight)
    let centerY = y + panelHeight / 2

    #expect(centerY == expectedCenterY)
    #expect(centerY < screen.midY)
    #expect(centerY > screen.midY - screen.height * 0.10)
  }

  @Test("construction is cheap and side-effect-free beyond font registration")
  @MainActor
  func constructionIsCheap() throws {
    guard let defaults = UserDefaults(suiteName: "test-\(UUID())") else {
      Issue.record("UserDefaults suite creation failed")
      return
    }
    let prefs = ThemePreferences(defaults: defaults)
    let tmpDir = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-swc-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let store = try ChatStore(directory: tmpDir)
    let shortcuts = ShortcutStore(defaults: defaults)
    _ = SpotlightWindowController(
      preferences: prefs,
      store: store,
      shortcuts: shortcuts,
      onOpenSettings: {}
    )
    #expect(Bool(true))
  }
}
