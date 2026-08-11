import AppKit
import Testing

@testable import Spotlight

/// The modal family's resign contract (critique r1 P1-3): TWO dismissal
/// layers -- the HUD's focus-loss handler and each child panel's resign
/// observer -- and with a submenu stacked on the actions panel, both
/// must treat key moving INSIDE the family as "not focus loss". These
/// drive the pure policy with real windows, no key loop needed.
@MainActor
struct ModalFocusPolicyTests {
  private func window() -> NSWindow {
    let made = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.borderless],
      backing: .buffered,
      defer: true
    )
    made.isReleasedWhenClosed = false
    return made
  }

  @Test("HUD focus loss: only key leaving the whole family counts")
  func panelFocusLoss() {
    let panel = window()
    let child = window()
    let foreign = window()
    let owned: (NSWindow?) -> Bool = { $0 === child }
    #expect(ModalFocusPolicy.isPanelFocusLoss(newKey: nil, panel: panel, isOwned: owned))
    #expect(!ModalFocusPolicy.isPanelFocusLoss(newKey: panel, panel: panel, isOwned: owned))
    #expect(!ModalFocusPolicy.isPanelFocusLoss(newKey: child, panel: panel, isOwned: owned))
    #expect(ModalFocusPolicy.isPanelFocusLoss(newKey: foreign, panel: panel, isOwned: owned))
  }

  @Test("parent modal panel: key moving to its submenu is not a dismissal")
  func childDismissal() {
    let submenu = window()
    let foreign = window()
    let owned: (NSWindow?) -> Bool = { $0 === submenu }
    #expect(ModalFocusPolicy.childShouldDismiss(newKey: nil, isOwned: owned))
    #expect(!ModalFocusPolicy.childShouldDismiss(newKey: submenu, isOwned: owned))
    #expect(ModalFocusPolicy.childShouldDismiss(newKey: foreign, isOwned: owned))
  }

  @Test("submenu resign: back-to-parent closes it, leaving the family closes all")
  func submenuReactions() {
    let parent = window()
    let sibling = window()
    let foreign = window()
    let owned: (NSWindow?) -> Bool = { $0 === parent || $0 === sibling }
    #expect(
      ModalFocusPolicy.submenuKeyLoss(newKey: nil, parentPanel: parent, isOwned: owned)
        == .dismissAll
    )
    #expect(
      ModalFocusPolicy.submenuKeyLoss(newKey: parent, parentPanel: parent, isOwned: owned)
        == .closeSubmenu
    )
    #expect(
      ModalFocusPolicy.submenuKeyLoss(newKey: sibling, parentPanel: parent, isOwned: owned)
        == .keep
    )
    #expect(
      ModalFocusPolicy.submenuKeyLoss(newKey: foreign, parentPanel: parent, isOwned: owned)
        == .dismissAll
    )
  }

  @Test("the owned-windows table tracks membership weakly")
  func ownedRegistry() {
    let member = window()
    #expect(!RaycastModalOverhang.isOwned(member))
    RaycastModalOverhang.ownedWindows.add(member)
    #expect(RaycastModalOverhang.isOwned(member))
    #expect(!RaycastModalOverhang.isOwned(nil))
    RaycastModalOverhang.ownedWindows.remove(member)
    #expect(!RaycastModalOverhang.isOwned(member))
  }
}
