// swiftlint:disable type_body_length
import Testing

@testable import Spotlight

@Suite("VimEngine visual character")
struct VimEngineVisualCharacterTests {
  // MARK: - Visual character mode

  @Test("v from normal enters characterwise visual mode")
  func enterVisualCharacter() {
    let engine = VimEngine()
    let action = engine.handle(key: "v", hasModifiers: false)
    #expect(action == .enterVisualCharacter)
    #expect(engine.mode == .visualCharacter)
  }

  @Test(
    "motions in characterwise visual mode produce extendVisualCharacter actions",
    arguments: [
      ("h", Motion.left(1)),
      ("l", Motion.right(1)),
      ("w", Motion.wordForward(1)),
      ("e", Motion.wordEnd(1)),
      ("G", Motion.documentEnd)
    ]
  )
  func visualCharacterMotions(key: String, expected: Motion) {
    let engine = VimEngine()
    _ = engine.handle(key: "v", hasModifiers: false)
    #expect(
      engine.handle(key: key, hasModifiers: false) == .extendVisualCharacter(expected)
    )
    #expect(engine.mode == .visualCharacter)
  }

  @Test("v in characterwise visual mode toggles back to normal")
  func visualCharacterToggleOff() {
    let engine = VimEngine()
    _ = engine.handle(key: "v", hasModifiers: false)
    let action = engine.handle(key: "v", hasModifiers: false)
    #expect(action == .switchToNormal)
    #expect(engine.mode == .normal)
  }

  @Test("c in characterwise visual mode changes selection and switches to insert")
  func visualCharacterChange() {
    let engine = VimEngine()
    _ = engine.handle(key: "v", hasModifiers: false)
    let action = engine.handle(key: "c", hasModifiers: false)
    #expect(action == .changeVisualCharacterSelection)
    #expect(engine.mode == .insert)
  }

}
