import AppKit
import SwiftUI

/// Borderless child panel for the floating modals; must be able to take
/// key so the modal search field can type.
final class RaycastModalChildPanel: NSPanel {
  /// Chords land HERE while a modal shows (this panel is key), never in
  /// the main panel's key-equivalent table. The presenter wires the
  /// HUD's handler so the actions-menu chord can toggle; unhandled
  /// chords keep today's inert behavior via super.
  var onKeyEquivalent: ((NSEvent) -> Bool)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let onKeyEquivalent, onKeyEquivalent(event) { return true }
    return super.performKeyEquivalent(with: event)
  }
}

/// Pure decision for chords arriving at a modal child panel, beside
/// `ModalFocusPolicy` for the same reason: testable without a key loop.
/// Only the actions-menu chord acts (Raycast's ⌘K toggles its menu);
/// every other chord stays inert, matching pre-⌘K behavior.
enum ModalKeyEquivalentPolicy {
  enum Reaction: Equatable {
    /// The browse modal is up: ⌘K replaces it with the actions menu.
    case switchToActions
    /// The actions menu is up: ⌘K closes it (the Raycast toggle).
    case toggleActions
    case ignore
  }

  static func reaction(action: ShortcutAction?, fuzzyVisible: Bool) -> Reaction {
    guard action == .openActions else { return .ignore }
    return fuzzyVisible ? .switchToActions : .toggleActions
  }
}

/// Pure decision table for the modal window family's key changes,
/// extracted so the resign contract is testable without a key loop.
/// Two independent dismissal layers consult it: the HUD controller's
/// focus-loss handler and each child panel's own resign observer --
/// with a submenu stacked on the actions panel, BOTH must agree that
/// key moving inside the family is not focus loss.
enum ModalFocusPolicy {
  /// The HUD panel family resigned key: real focus loss (dim/close per
  /// preference) only when key left every window we own.
  static func isPanelFocusLoss(
    newKey: NSWindow?,
    panel: NSWindow?,
    isOwned: (NSWindow?) -> Bool
  ) -> Bool {
    guard let newKey else { return true }
    if newKey === panel { return false }
    return !isOwned(newKey)
  }

  /// A modal child panel resigned key: the modal dismisses unless key
  /// moved to another family window (its own submenu, or back to the
  /// parent panel that will re-present).
  static func childShouldDismiss(newKey: NSWindow?, isOwned: (NSWindow?) -> Bool) -> Bool {
    guard let newKey else { return true }
    return !isOwned(newKey)
  }

  /// The submenu panel resigned key.
  enum SubmenuReaction {
    /// Key moved deeper into the family (another owned window): stay.
    case keep
    /// Key returned to the parent modal panel: close just the submenu.
    case closeSubmenu
    /// Key left the family: the whole modal stack dismisses.
    case dismissAll
  }

  static func submenuKeyLoss(
    newKey: NSWindow?,
    parentPanel: NSWindow?,
    isOwned: (NSWindow?) -> Bool
  ) -> SubmenuReaction {
    guard let newKey else { return .dismissAll }
    if newKey === parentPanel { return .closeSubmenu }
    if isOwned(newKey) { return .keep }
    return .dismissAll
  }
}

/// Presents the floating Raycast modal in a CHILD WINDOW that overhangs
/// the HUD, exactly like the live app: the sheet top sits
/// `RaycastModalPalette.topOffset` below the window top and the sheet
/// extends past the parent's bottom edge freely (the live actions menu is
/// ~427pt taller than the empty note window). Installed as an invisible
/// `.background` so the modal never touches the measured height tree.
struct RaycastModalOverhang: NSViewRepresentable {
  /// The modal sheet to present, or nil to dismiss.
  let content: AnyView?
  let onDismissTap: () -> Void
  /// Key-equivalent handler installed on the child panel (see
  /// `RaycastModalChildPanel.onKeyEquivalent`).
  let onKeyEquivalent: (NSEvent) -> Bool

  /// Transparent margin around the sheet; taps here dismiss, like the
  /// parent window's tap-catch. (The drop shadow is the window server's
  /// and draws regardless of this margin.)
  static let margin: CGFloat = 40
  static let height: CGFloat = 560

  /// Every live window the modal family owns (the actions/browse child
  /// panel plus any stacked submenu panel). The HUD's resign-key handler
  /// and each panel's own resign observer consult membership, so key
  /// moving BETWEEN family windows never dims or closes anything. A weak
  /// table: a dying panel drops out on its own.
  @MainActor static let ownedWindows = NSHashTable<NSWindow>.weakObjects()

  @MainActor static func isOwned(_ window: NSWindow?) -> Bool {
    guard let window else { return false }
    return ownedWindows.contains(window)
  }

  func makeNSView(context: Context) -> NSView { NSView() }

  func updateNSView(_ view: NSView, context: Context) {
    let coordinator = context.coordinator
    let content = content
    let onDismissTap = onDismissTap
    let onKeyEquivalent = onKeyEquivalent
    DispatchQueue.main.async {
      coordinator.update(
        content: content,
        anchor: view.window,
        onDismissTap: onDismissTap,
        onKeyEquivalent: onKeyEquivalent
      )
    }
  }

  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
    coordinator.update(content: nil, anchor: nil, onDismissTap: {}, onKeyEquivalent: { _ in false })
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  @MainActor final class Coordinator {
    private var child: RaycastModalChildPanel?
    private var onDismissTap: () -> Void = {}
    private var onKeyEquivalent: (NSEvent) -> Bool = { _ in false }
    private var resignObserver: NSObjectProtocol?

    func update(
      content: AnyView?,
      anchor: NSWindow?,
      onDismissTap: @escaping () -> Void,
      onKeyEquivalent: @escaping (NSEvent) -> Bool
    ) {
      self.onDismissTap = onDismissTap
      self.onKeyEquivalent = onKeyEquivalent
      child?.onKeyEquivalent = onKeyEquivalent
      guard let content else {
        dismiss(returnKeyTo: anchor)
        return
      }
      guard let anchor else { return }
      let root = RaycastModalOverhangRoot(
        content: content,
        onDismissTap: { [weak self] in
          self?.onDismissTap()
        }
      )
      if let child {
        (child.contentView as? NSHostingView<RaycastModalOverhangRoot>)?.rootView = root
        // Shadowless panel (see present) -- no shadow invalidation on
        // frame changes; the old per-update calls were a WindowServer
        // round-trip that stuttered in-sheet scrolling.
        position(child, over: anchor)
        return
      }
      present(root, over: anchor)
    }

    private func present(_ root: RaycastModalOverhangRoot, over anchor: NSWindow) {
      let panel = RaycastModalChildPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      panel.isOpaque = false
      panel.backgroundColor = .clear
      // NO window-server shadow: its hard contact rim drew a 1-2px
      // near-black ring hugging the sheet border (round-12 edge profile:
      // (4,4,6)/(11,11,12) just outside our stroke) that the live menu
      // does not have -- Raycast's popover transitions backdrop ->
      // border -> sheet directly; its own CSS shadow (10-20% black,
      // soft) is invisible against the dark desk.
      panel.hasShadow = false
      panel.onKeyEquivalent = onKeyEquivalent
      // The overhang root is its OWN hosting tree: the HUD's
      // `.colorScheme(.dark)` does not reach it, and the sheet material
      // must stay dark in system light mode.
      panel.appearance = NSAppearance(named: .darkAqua)
      panel.level = anchor.level
      panel.isReleasedWhenClosed = false
      let hosting = NSHostingView(rootView: root)
      hosting.sizingOptions = []
      panel.contentView = hosting
      anchor.addChildWindow(panel, ordered: .above)
      position(panel, over: anchor)
      panel.makeKey()
      child = panel
      RaycastModalOverhang.ownedWindows.add(panel)
      // Losing key while presented = the user clicked outside the menu
      // (back into the note, or away entirely): dismiss, like Raycast --
      // UNLESS key moved to a stacked family window (the submenu panel).
      // The transfer may still be in flight when the notification fires,
      // so the decision waits one runloop tick.
      resignObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: panel,
        queue: .main
      ) { [weak self] _ in
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            guard let self, self.child != nil else { return }
            guard
              ModalFocusPolicy.childShouldDismiss(
                newKey: NSApp.keyWindow,
                isOwned: RaycastModalOverhang.isOwned
              )
            else { return }
            self.onDismissTap()
          }
        }
      }
    }

    private func position(_ panel: NSPanel, over anchor: NSWindow) {
      let width = RaycastModalPalette.width + RaycastModalOverhang.margin * 2
      let sheetTopY = anchor.frame.maxY - RaycastModalPalette.topOffset
      var frame = NSRect(
        x: anchor.frame.midX - width / 2,
        y: sheetTopY + RaycastModalOverhang.margin - RaycastModalOverhang.height,
        width: width,
        height: RaycastModalOverhang.height
      )
      // The HUD is bottom-pinned and an empty note is only 177pt tall, so
      // anchoring the sheet 100pt below its top would push most of the
      // menu past the display edge. Slide the sheet up until its content
      // fits; covering the note body is fine -- Raycast's own menu does.
      if let screen = anchor.screen {
        frame.origin.y = max(frame.origin.y, screen.visibleFrame.minY - RaycastModalOverhang.margin)
      }
      guard frame != panel.frame else { return }
      panel.setFrame(frame, display: true)
    }

    private func dismiss(returnKeyTo anchor: NSWindow?) {
      guard let child else { return }
      if let observer = resignObserver {
        NotificationCenter.default.removeObserver(observer)
        resignObserver = nil
      }
      child.parent?.removeChildWindow(child)
      child.orderOut(nil)
      self.child = nil
      RaycastModalOverhang.ownedWindows.remove(child)
      // Return key to the note -- but never steal it back when the user
      // switched to another app while the menu was open.
      if let anchor, anchor.isVisible, NSApp.isActive {
        anchor.makeKey()
      }
    }
  }
}

/// Child-window root: transparent margin (tap = dismiss) around the sheet,
/// top-aligned so the sheet top lands at the probed offset.
private struct RaycastModalOverhangRoot: View {
  let content: AnyView
  let onDismissTap: () -> Void

  var body: some View {
    ZStack(alignment: .top) {
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismissTap)
      content
        .padding(.top, RaycastModalOverhang.margin)
    }
    .frame(
      width: RaycastModalPalette.width + RaycastModalOverhang.margin * 2,
      height: RaycastModalOverhang.height,
      alignment: .top
    )
  }
}
