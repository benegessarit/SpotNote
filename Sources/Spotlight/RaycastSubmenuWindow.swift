import AppKit
import SwiftUI

/// Presents the flyout submenu in a SECOND child panel stacked on the
/// actions modal's panel -- new plumbing beside `RaycastModalOverhang`
/// (whose coordinator is single-child by design). Installed as a
/// `.background` on the INVOKING ROW, so the row's own frame anchors
/// the flyout: the submenu's dimmed header lands where the row is,
/// which is exactly how Raycast's "Change Model…" expands in place.
struct RaycastSubmenuOverhang: NSViewRepresentable {
  let model: SpotNoteSubmenu
  let onCommit: (SpotNoteCommand) -> Void
  /// Close just the submenu (Esc/←/click back on the parent).
  let onClose: () -> Void
  /// Key left the whole modal family: the full stack dismisses.
  let onDismissAll: () -> Void

  /// Transparent margin around the sheet; taps here fall back to the
  /// parent menu.
  static let margin: CGFloat = 40
  /// Header text center sits 23.75pt below the sheet top (probed), and
  /// the sheet is placed so that center rides the invoking row's center.
  static let headerAnchor: CGFloat = 23.75

  func makeNSView(context: Context) -> NSView { NSView() }

  func updateNSView(_ view: NSView, context: Context) {
    let coordinator = context.coordinator
    let payload = self
    DispatchQueue.main.async {
      coordinator.update(payload, anchorView: view)
    }
  }

  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
    coordinator.dismiss()
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  @MainActor final class Coordinator {
    private var child: RaycastModalChildPanel?
    private weak var parentPanel: NSWindow?
    private var resignObserver: NSObjectProtocol?
    private var onClose: () -> Void = {}
    private var onDismissAll: () -> Void = {}

    func update(_ payload: RaycastSubmenuOverhang, anchorView: NSView?) {
      onClose = payload.onClose
      onDismissAll = payload.onDismissAll
      guard let anchorView, let window = anchorView.window else { return }
      let root = submenuRoot(payload, listCap: listCap(for: window))
      if let child {
        (child.contentView as? NSHostingView<AnyView>)?.rootView = root
        position(child, payload: payload, anchorView: anchorView)
        return
      }
      present(root, payload: payload, anchorView: anchorView, parent: window)
    }

    private func submenuRoot(_ payload: RaycastSubmenuOverhang, listCap: CGFloat) -> AnyView {
      AnyView(
        RaycastSubmenuRoot(
          model: payload.model,
          maxListHeight: listCap,
          onCommit: payload.onCommit,
          onClose: payload.onClose
        )
      )
    }

    /// Row list cap so the whole sheet (plus margins) fits the screen.
    private func listCap(for window: NSWindow) -> CGFloat {
      guard let screen = window.screen ?? NSScreen.main else { return 600 }
      return screen.visibleFrame.height
        - RaycastSubmenuMetrics.headerHeight
        - RaycastSubmenuMetrics.searchHeight
        - RaycastSubmenuOverhang.margin * 2
    }

    private func present(
      _ root: AnyView,
      payload: RaycastSubmenuOverhang,
      anchorView: NSView,
      parent: NSWindow
    ) {
      let panel = RaycastModalChildPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.appearance = NSAppearance(named: .darkAqua)
      panel.level = parent.level
      panel.isReleasedWhenClosed = false
      let hosting = NSHostingView(rootView: root)
      hosting.sizingOptions = []
      panel.contentView = hosting
      parent.addChildWindow(panel, ordered: .above)
      position(panel, payload: payload, anchorView: anchorView)
      panel.makeKey()
      child = panel
      parentPanel = parent
      RaycastModalOverhang.ownedWindows.add(panel)
      observeResign(of: panel)
    }

    /// The submenu resigning key routes through the shared policy: back
    /// to the parent closes just the flyout, leaving the family closes
    /// everything. Deferred a tick -- the key transfer may still be in
    /// flight when the notification fires.
    private func observeResign(of panel: NSPanel) {
      resignObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: panel,
        queue: .main
      ) { [weak self] _ in
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            guard let self, self.child != nil else { return }
            switch ModalFocusPolicy.submenuKeyLoss(
              newKey: NSApp.keyWindow,
              parentPanel: self.parentPanel,
              isOwned: RaycastModalOverhang.isOwned
            ) {
            case .keep: break
            case .closeSubmenu: self.onClose()
            case .dismissAll: self.onDismissAll()
            }
          }
        }
      }
    }

    /// The sheet rides the invoking row: header text center on the
    /// row's center, sheet horizontally centered over the parent sheet
    /// (the 419pt flyout overhangs the 383pt menu evenly), clamped to
    /// the screen.
    private func position(
      _ panel: NSPanel,
      payload: RaycastSubmenuOverhang,
      anchorView: NSView
    ) {
      guard let window = anchorView.window else { return }
      let margin = RaycastSubmenuOverhang.margin
      let rowFrame = window.convertToScreen(
        anchorView.convert(anchorView.bounds, to: nil)
      )
      let sheetHeight = RaycastSubmenu.sheetHeight(
        for: payload.model,
        maxListHeight: listCap(for: window)
      )
      let width = RaycastSubmenuMetrics.width + margin * 2
      let sheetTopY = rowFrame.midY + RaycastSubmenuOverhang.headerAnchor
      var frame = NSRect(
        x: window.frame.midX - width / 2,
        y: sheetTopY + margin - (sheetHeight + margin * 2),
        width: width,
        height: sheetHeight + margin * 2
      )
      if let screen = window.screen ?? NSScreen.main {
        frame.origin.y = max(frame.origin.y, screen.visibleFrame.minY - margin)
        let maxY = screen.visibleFrame.maxY + margin
        frame.origin.y = min(frame.origin.y, maxY - frame.height)
      }
      guard frame != panel.frame else { return }
      panel.setFrame(frame, display: true)
    }

    func dismiss() {
      guard let child else { return }
      if let observer = resignObserver {
        NotificationCenter.default.removeObserver(observer)
        resignObserver = nil
      }
      child.parent?.removeChildWindow(child)
      child.orderOut(nil)
      self.child = nil
      RaycastModalOverhang.ownedWindows.remove(child)
      // Key returns to the parent menu panel, never stolen from another
      // app the user switched to.
      if let parentPanel, parentPanel.isVisible, NSApp.isActive {
        parentPanel.makeKey()
      }
    }
  }
}

/// Child-window root: transparent margin around the sheet; a tap there
/// walks back to the parent menu (the parent's own tap-catch and resign
/// policy handle true outside clicks).
private struct RaycastSubmenuRoot: View {
  let model: SpotNoteSubmenu
  let maxListHeight: CGFloat
  let onCommit: (SpotNoteCommand) -> Void
  let onClose: () -> Void

  var body: some View {
    ZStack(alignment: .top) {
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
      RaycastSubmenu(
        model: model,
        maxListHeight: maxListHeight,
        onCommit: onCommit,
        onClose: onClose
      )
      .padding(.top, RaycastSubmenuOverhang.margin)
    }
    .frame(
      width: RaycastSubmenuMetrics.width + RaycastSubmenuOverhang.margin * 2,
      alignment: .top
    )
    .frame(maxHeight: .infinity, alignment: .top)
  }
}
