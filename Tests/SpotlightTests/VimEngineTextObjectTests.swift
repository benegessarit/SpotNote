import Testing

@testable import Spotlight

@Suite("VimEngine text objects and wrappers")
struct VimEngineTextObjectTests {
  @Test("ciw changes inner word and enters insert")
  func ciwChangesInnerWord() {
    let engine = VimEngine()
    #expect(engine.handle(key: "c", hasModifiers: false) == .none)
    #expect(engine.handle(key: "i", hasModifiers: false) == .none)
    #expect(engine.handle(key: "w", hasModifiers: false) == .changeTextObject(.innerWord))
    #expect(engine.mode == .insert)
  }

  @Test("diw deletes inner word")
  func diwDeletesInnerWord() {
    let engine = VimEngine()
    #expect(engine.handle(key: "d", hasModifiers: false) == .none)
    #expect(engine.handle(key: "i", hasModifiers: false) == .none)
    #expect(engine.handle(key: "w", hasModifiers: false) == .deleteTextObject(.innerWord))
    #expect(engine.mode == .normal)
  }

  @Test("semicolon wrappers format current word")
  func semicolonFormatsCurrentWord() {
    let engine = VimEngine()
    #expect(engine.handle(key: ";", hasModifiers: false) == .none)
    #expect(engine.handle(key: "b", hasModifiers: false) == .wrapCurrentWord(.bold))
    #expect(engine.handle(key: ";", hasModifiers: false) == .none)
    #expect(engine.handle(key: "i", hasModifiers: false) == .wrapCurrentWord(.italic))
  }
}
