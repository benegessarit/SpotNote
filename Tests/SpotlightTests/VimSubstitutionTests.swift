import Testing

@testable import Spotlight

@Suite("Vim substitute command")
struct VimSubstitutionTests {
  @Test("global substitution whose replacement contains the pattern terminates and matches vim counts")
  func globalSelfContainingReplacementTerminates() {
    // Previously `:s/a/aa/g` looped forever because the scan restarted at the
    // newly inserted replacement. It must now advance past it: 3 a's -> 6 a's.
    #expect(VimSubstitution.apply(to: "aaa", pattern: "a", replacement: "aa", replaceAll: true) == ("aaaaaa", 3))
  }

  @Test("global single-occurrence replacement that contains the pattern substitutes once")
  func globalSingleSelfContainingReplacement() {
    #expect(VimSubstitution.apply(to: "a", pattern: "a", replacement: "ba", replaceAll: true) == ("ba", 1))
    #expect(VimSubstitution.apply(to: "x", pattern: "x", replacement: "xy", replaceAll: true) == ("xy", 1))
  }

  @Test("global empty replacement deletes every match and terminates")
  func globalEmptyReplacementDeletesAll() {
    #expect(VimSubstitution.apply(to: "aaa", pattern: "a", replacement: "", replaceAll: true) == ("", 3))
  }

  @Test("global substitution of overlapping patterns advances past each replacement")
  func globalOverlappingPattern() {
    #expect(VimSubstitution.apply(to: "aaaa", pattern: "aa", replacement: "x", replaceAll: true) == ("xx", 2))
  }

  @Test("substitution is literal, not regular-expression")
  func substitutionIsLiteral() {
    // A literal "." replaces only real dots, never every character.
    #expect(VimSubstitution.apply(to: "a.b.c", pattern: ".", replacement: "-", replaceAll: true) == ("a-b-c", 2))
  }

  @Test("non-global substitution replaces only the first match on each line")
  func nonGlobalReplacesFirstOnly() {
    #expect(VimSubstitution.apply(to: "aaa", pattern: "a", replacement: "b", replaceAll: false) == ("baa", 1))
  }

  @Test("substitution applies independently to each line")
  func appliesPerLine() {
    #expect(VimSubstitution.apply(to: "a\na", pattern: "a", replacement: "b", replaceAll: true) == ("b\nb", 2))
    #expect(VimSubstitution.apply(to: "a\na", pattern: "a", replacement: "aa", replaceAll: true) == ("aa\naa", 2))
  }

  @Test("pattern with no match leaves the input unchanged")
  func noMatchIsUnchanged() {
    #expect(VimSubstitution.apply(to: "abc", pattern: "z", replacement: "q", replaceAll: true) == ("abc", 0))
  }

  @Test("an empty pattern is a no-op")
  func emptyPatternIsNoOp() {
    #expect(VimSubstitution.apply(to: "abc", pattern: "", replacement: "x", replaceAll: true) == ("abc", 0))
  }
}
