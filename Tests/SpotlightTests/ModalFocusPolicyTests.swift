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

/// ⌘K Raycast parity: while a modal shows, its CHILD panel is key, so
/// chords bypass the main panel's key-equivalent table entirely. The
/// panel consults an installed handler, and the pure policy decides --
/// same shape as `ModalFocusPolicy`, testable without a key loop.
@MainActor
struct ModalKeyEquivalentTests {
  private func cmdKEvent() -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "k",
      charactersIgnoringModifiers: "k",
      isARepeat: false,
      keyCode: 40
    )
  }

  @Test("only the actions-menu chord acts: switch over browse, toggle over actions")
  func policyReactions() {
    #expect(
      ModalKeyEquivalentPolicy.reaction(action: .openActions, fuzzyVisible: true)
        == .switchToActions
    )
    #expect(
      ModalKeyEquivalentPolicy.reaction(action: .openActions, fuzzyVisible: false)
        == .toggleActions
    )
    #expect(ModalKeyEquivalentPolicy.reaction(action: .newNote, fuzzyVisible: false) == .ignore)
    #expect(ModalKeyEquivalentPolicy.reaction(action: nil, fuzzyVisible: true) == .ignore)
  }

  @Test("the child panel consults its key-equivalent handler before super")
  func childPanelConsultsHandler() throws {
    let panel = RaycastModalChildPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    panel.isReleasedWhenClosed = false
    let event = try #require(cmdKEvent())
    var seen: [String] = []
    panel.onKeyEquivalent = { chord in
      seen.append(chord.charactersIgnoringModifiers ?? "")
      return true
    }
    #expect(panel.performKeyEquivalent(with: event))
    #expect(seen == ["k"])

    panel.onKeyEquivalent = { _ in false }
    #expect(!panel.performKeyEquivalent(with: event), "unhandled chords stay inert")
  }
}
