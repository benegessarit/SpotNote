import Testing

@testable import Spotlight

@Suite("VimEngine paste")
struct VimEnginePasteTests {
  @Test("p pastes after the cursor")
  func pPastesAfterCursor() {
    let engine = VimEngine()

    #expect(engine.handle(key: "p", hasModifiers: false) == .pasteAfter(count: 1))
    #expect(engine.mode == .normal)
  }

  @Test("count p repeats the paste")
  func countedPasteAfterCursor() {
    let engine = VimEngine()

    #expect(engine.handle(key: "3", hasModifiers: false) == .none)
    #expect(engine.handle(key: "p", hasModifiers: false) == .pasteAfter(count: 3))
    #expect(engine.mode == .normal)
  }
}
