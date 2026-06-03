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

  @Test("caw changes a word and enters insert")
  func cawChangesAWord() {
    let engine = VimEngine()
    #expect(engine.handle(key: "c", hasModifiers: false) == .none)
    #expect(engine.handle(key: "a", hasModifiers: false) == .none)
    #expect(engine.handle(key: "w", hasModifiers: false) == .changeTextObject(.aroundWord))
    #expect(engine.mode == .insert)
  }

  @Test("all sentence and paragraph text objects parse for change and delete")
  func allSentenceAndParagraphTextObjectsParse() {
    #expect(parse("cis") == .changeTextObject(.innerSentence))
    #expect(parse("cas") == .changeTextObject(.aroundSentence))
    #expect(parse("cip") == .changeTextObject(.innerParagraph))
    #expect(parse("cap") == .changeTextObject(.aroundParagraph))
    #expect(parse("dis") == .deleteTextObject(.innerSentence))
    #expect(parse("das") == .deleteTextObject(.aroundSentence))
    #expect(parse("dip") == .deleteTextObject(.innerParagraph))
    #expect(parse("dap") == .deleteTextObject(.aroundParagraph))
  }

  @Test("semicolon wrappers format current word")
  func semicolonFormatsCurrentWord() {
    let engine = VimEngine()
    #expect(engine.handle(key: ";", hasModifiers: false) == .none)
    #expect(engine.handle(key: "b", hasModifiers: false) == .wrapCurrentWord(.bold))
    #expect(engine.handle(key: ";", hasModifiers: false) == .none)
    #expect(engine.handle(key: "i", hasModifiers: false) == .wrapCurrentWord(.italic))
  }

  private func parse(_ keys: String) -> VimAction {
    let engine = VimEngine()
    var action: VimAction = .none
    for key in keys.map(String.init) {
      action = engine.handle(key: key, hasModifiers: false)
    }
    return action
  }
}
