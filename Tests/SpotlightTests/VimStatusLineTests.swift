import Testing

@testable import Spotlight

@Suite("Vim status line")
struct VimStatusLineTests {
  @Test("regular Flash prompt chrome does not prepend the s trigger to the query")
  func regularFlashPromptPrefixOmitsTriggerKey() {
    #expect(VimPromptDisplay.prefix(for: .flash(.forward, count: 1, scope: .document)) == "⚡ ")
    #expect(VimPromptDisplay.prefix(for: .flash(.backward, count: 3, scope: .document)) == "3⚡ ")
    #expect(VimPromptDisplay.prefix(for: .flash(.forward, count: 1, scope: .currentLine)) == "⚡ ")
  }
}
