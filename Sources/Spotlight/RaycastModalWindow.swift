import AppKit
import SwiftUI

/// Borderless child panel for the floating modals; must be able to take
/// key so the modal search field can type.
final class RaycastModalChildPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
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

  /// Transparent margin around the sheet; taps here dismiss, like the
  /// parent window's tap-catch. (The drop shadow is the window server's
  /// and draws regardless of this margin.)
  static let margin: CGFloat = 40
  static let height: CGFloat = 560

  /// The presented child window, if any -- the window controller's
  /// resign-key handler consults this so the modal taking key never
  /// dims or closes the HUD.
  @MainActor static private(set) weak var activeChildWindow: NSWindow?

  func makeNSView(context: Context) -> NSView { NSView() }

  func updateNSView(_ view: NSView, context: Context) {
    let coordinator = context.coordinator
    let content = content
    let onDismissTap = onDismissTap
    DispatchQueue.main.async {
      coordinator.update(content: content, anchor: view.window, onDismissTap: onDismissTap)
    }
  }

  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
    coordinator.update(content: nil, anchor: nil, onDismissTap: {})
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  @MainActor final class Coordinator {
    private var child: RaycastModalChildPanel?
    private var onDismissTap: () -> Void = {}
    private var resignObserver: NSObjectProtocol?

    func update(content: AnyView?, anchor: NSWindow?, onDismissTap: @escaping () -> Void) {
      self.onDismissTap = onDismissTap
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
        let framedMoved = position(child, over: anchor)
        // invalidateShadow is a WindowServer round-trip; per-update calls
        // (every keystroke/hover re-runs updateNSView) stutter scrolling
        // inside the sheet. The shadow shape only changes when the panel
        // frame does.
        if framedMoved { child.invalidateShadow() }
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
      // Window-server shadow, shaped by the sheet's opaque region -- the
      // sheet background is a behind-window material, so a SwiftUI
      // .shadow can't draw it.
      panel.hasShadow = true
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
      RaycastModalOverhang.activeChildWindow = panel
      // Losing key while presented = the user clicked outside the menu
      // (back into the note, or away entirely): dismiss, like Raycast.
      resignObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: panel,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.onDismissTap() }
      }
    }

    @discardableResult
    private func position(_ panel: NSPanel, over anchor: NSWindow) -> Bool {
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
      guard frame != panel.frame else { return false }
      panel.setFrame(frame, display: true)
      return true
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
      if RaycastModalOverhang.activeChildWindow === child {
        RaycastModalOverhang.activeChildWindow = nil
      }
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
