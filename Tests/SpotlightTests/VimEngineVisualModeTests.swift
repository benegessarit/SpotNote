import Testing

@testable import Spotlight

@Suite("VimEngine visual character mode")
struct VimEngineVisualModeTests {
  @Test("v from normal enters visual character mode")
  func enterVisualCharacterMode() {
    let engine = VimEngine()

    let action = engine.handle(key: "v", hasModifiers: false)

    #expect(action == .enterVisual)
    #expect(engine.mode == .visual)
  }

  @Test(
    "motions in visual character mode extend the characterwise range",
    arguments: [
      ("h", Motion.left(1)),
      ("l", Motion.right(1)),
      ("w", Motion.wordForward(1)),
      ("e", Motion.wordEnd(1)),
      ("$", Motion.lineEnd)
    ]
  )
  func visualCharacterMotions(key: String, expected: Motion) {
    let engine = VimEngine()
    _ = engine.handle(key: "v", hasModifiers: false)

    #expect(engine.handle(key: key, hasModifiers: false) == .extendVisual(expected))
    #expect(engine.mode == .visual)
  }

  @Test("v in visual character mode toggles back to normal")
  func visualCharacterToggleOff() {
    let engine = VimEngine()
    _ = engine.handle(key: "v", hasModifiers: false)

    let action = engine.handle(key: "v", hasModifiers: false)

    #expect(action == .switchToNormal)
    #expect(engine.mode == .normal)
  }

  @Test("V in visual character mode switches to full-line visual mode")
  func visualCharacterSwitchesToVisualLine() {
    let engine = VimEngine()
    _ = engine.handle(key: "v", hasModifiers: false)

    let action = engine.handle(key: "V", hasModifiers: false)

    #expect(action == .enterVisualLine)
    #expect(engine.mode == .visualLine)
  }
}
