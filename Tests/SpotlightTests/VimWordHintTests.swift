import AppKit
import Testing

@testable import Spotlight

@Suite("VimWordHint")
struct VimWordHintTests {
  // MARK: - Label permutations (hop TrieBacktrackFilling)

  // Ground-truth vectors generated from the live hop.nvim plugin
  // (`require("hop.perm").TrieBacktrackFilling:permutations(...)`,
  // 2026-08-08) so the Swift port stays byte-identical to nvim.
  @Test("permutations match hop.nvim ground truth (small keyset)")
  func permutationGroundTruthSmallKeyset() {
    let abc: [Character] = ["a", "b", "c"]
    #expect(VimWordHint.labelPermutations(count: 1, keys: abc) == ["a"])
    #expect(VimWordHint.labelPermutations(count: 3, keys: abc) == ["a", "b", "c"])
    #expect(VimWordHint.labelPermutations(count: 4, keys: abc) == ["a", "b", "ca", "cb"])
    #expect(
      VimWordHint.labelPermutations(count: 6, keys: abc) == ["a", "ba", "bb", "ca", "cb", "cc"]
    )
    #expect(
      VimWordHint.labelPermutations(count: 10, keys: abc)
        == ["aa", "ab", "ac", "ba", "bb", "bc", "ca", "cb", "cca", "ccb"]
    )
  }

  @Test("permutations match hop.nvim ground truth (full charset)")
  func permutationGroundTruthFullCharset() {
    let singles = "asdghklqwertyuiopzxcvbnmf".map(String.init)
    #expect(
      VimWordHint.labelPermutations(count: 26) == singles + ["j"]
    )
    #expect(
      VimWordHint.labelPermutations(count: 27) == singles + ["ja", "js"]
    )
    #expect(
      VimWordHint.labelPermutations(count: 30) == singles + ["ja", "js", "jd", "jg", "jh"]
    )
  }

  @Test("permutation label sets are prefix-free and unique")
  func permutationPrefixFree() {
    let labels = VimWordHint.labelPermutations(count: 120)
    #expect(labels.count == 120)
    #expect(Set(labels).count == 120)
    for lhs in labels {
      for rhs in labels where lhs != rhs {
        #expect(!rhs.hasPrefix(lhs), "\(lhs) is a prefix of \(rhs)")
      }
    }
  }

  // MARK: - Word-start scanning

  private func fullRange(_ text: String) -> NSRange {
    NSRange(location: 0, length: (text as NSString).length)
  }

  @Test("word starts at keyword runs after non-keyword boundaries")
  func wordStartScanning() {
    #expect(VimWordHint.wordStartLocations(in: "hello world", range: fullRange("hello world")) == [0, 6])
    #expect(VimWordHint.wordStartLocations(in: "  leading", range: fullRange("  leading")) == [2])
    #expect(
      VimWordHint.wordStartLocations(in: "foo, bar-baz", range: fullRange("foo, bar-baz")) == [0, 5, 9]
    )
    #expect(VimWordHint.wordStartLocations(in: "a_b c", range: fullRange("a_b c")) == [0, 4])
    #expect(
      VimWordHint.wordStartLocations(in: "line one\nline two", range: fullRange("line one\nline two"))
        == [0, 5, 9, 14]
    )
    #expect(VimWordHint.wordStartLocations(in: "", range: NSRange(location: 0, length: 0)).isEmpty)
  }

  @Test("word starts respect a bounded range and mid-word entry")
  func wordStartRangeBounds() {
    let text = "hello world"
    #expect(VimWordHint.wordStartLocations(in: text, range: NSRange(location: 6, length: 5)) == [6])
    // Entering mid-word: "ello…" continues the word started before the
    // range, so only "world" counts.
    #expect(VimWordHint.wordStartLocations(in: text, range: NSRange(location: 1, length: 10)) == [6])
  }

  // MARK: - Positions

  @Test("position maps UTF-16 offsets to row/col")
  func positionMapping() {
    let text = "ab\ncd"
    #expect(VimWordHint.position(of: 0, in: text) == VimWordHint.Position(row: 0, col: 0))
    #expect(VimWordHint.position(of: 2, in: text) == VimWordHint.Position(row: 0, col: 2))
    #expect(VimWordHint.position(of: 3, in: text) == VimWordHint.Position(row: 1, col: 0))
    #expect(VimWordHint.position(of: 4, in: text) == VimWordHint.Position(row: 1, col: 1))
  }

  // MARK: - Hint assignment (nearest-first, Manhattan distance, x_bias 10)

  @Test("nearest targets receive the earliest labels")
  func nearestFirstAssignment() {
    let text = "aa bb cc"
    let fromStart = VimWordHint.hints(targetLocations: [0, 3, 6], cursorLocation: 0, text: text)
    #expect(fromStart.map(\.label) == ["a", "s", "d"])
    let fromEnd = VimWordHint.hints(targetLocations: [0, 3, 6], cursorLocation: 6, text: text)
    #expect(fromEnd.map(\.label) == ["d", "s", "a"])
  }

  @Test("row distance outweighs column distance by the x_bias factor")
  func rowBiasScoring() {
    // Word at column 16 on the cursor row scores 16; word at column 0 on
    // the next row scores 10 -- the next-row word is "nearer" under hop's
    // Manhattan distance with x_bias 10.
    let text = "a               b\nc"
    let hints = VimWordHint.hints(targetLocations: [0, 16, 18], cursorLocation: 0, text: text)
    #expect(hints.map(\.label) == ["a", "d", "s"])
  }

  @Test("document order is preserved in the returned hint list")
  func documentOrderPreserved() {
    let text = "aa bb cc"
    let hints = VimWordHint.hints(targetLocations: [0, 3, 6], cursorLocation: 6, text: text)
    #expect(hints.map(\.location) == [0, 3, 6])
  }

  // MARK: - Touching-run alternation

  private func positions(_ pairs: [(Int, Int)]) -> [VimWordHint.Position] {
    pairs.map { VimWordHint.Position(row: $0.0, col: $0.1) }
  }

  @Test("adjacent labels alternate; separated labels do not")
  func touchingRunAlternation() {
    #expect(
      VimWordHint.alternateFlags(
        positions: positions([(0, 0), (0, 2)]),
        labels: ["ab", "cd"]
      ) == [false, true]
    )
    #expect(
      VimWordHint.alternateFlags(
        positions: positions([(0, 0), (0, 5)]),
        labels: ["a", "s"]
      ) == [false, false]
    )
    #expect(
      VimWordHint.alternateFlags(
        positions: positions([(0, 0), (1, 0)]),
        labels: ["ab", "cd"]
      ) == [false, false]
    )
  }

  @Test("a touching run alternates every other hint")
  func touchingRunEveryOther() {
    #expect(
      VimWordHint.alternateFlags(
        positions: positions([(0, 0), (0, 2), (0, 4)]),
        labels: ["ab", "cd", "ef"]
      ) == [false, true, false]
    )
  }

  @Test("alternation flags map back to the caller's original order")
  func alternationInputOrderIndependent() {
    let flags = VimWordHint.alternateFlags(
      positions: positions([(0, 2), (0, 0)]),
      labels: ["cd", "ab"]
    )
    #expect(flags == [true, false])
  }
}

@Suite("VimEngine word-hint bindings")
struct VimEngineWordHintBindingTests {
  @Test("normal-mode s enters the word-hint jump")
  func normalModeS() {
    let engine = VimEngine()
    #expect(engine.handle(key: "s", hasModifiers: false) == .enterWordHint)
  }

  @Test("S keeps the backward flash search")
  func backwardFlashUnchanged() {
    let engine = VimEngine()
    #expect(
      engine.handle(key: "S", hasModifiers: false)
        == .enterFlash(.backward, count: 1, scope: .document)
    )
  }

  @Test("visual-mode s enters the word-hint jump and stays visual")
  func visualModeS() {
    let engine = VimEngine()
    _ = engine.handle(key: "v", hasModifiers: false)
    #expect(engine.handle(key: "s", hasModifiers: false) == .enterWordHint)
    #expect(engine.mode == .visual)
  }

  @Test("visual-line-mode s enters the word-hint jump and stays visual line")
  func visualLineModeS() {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    #expect(engine.handle(key: "s", hasModifiers: false) == .enterWordHint)
    #expect(engine.mode == .visualLine)
  }

  @Test("visual-mode c still changes the selection")
  func visualModeChangeUnchanged() {
    let engine = VimEngine()
    _ = engine.handle(key: "v", hasModifiers: false)
    #expect(engine.handle(key: "s", hasModifiers: false) == .enterWordHint)
    _ = engine.handle(key: "\u{1B}", hasModifiers: false)
    _ = engine.handle(key: "v", hasModifiers: false)
    #expect(engine.handle(key: "c", hasModifiers: false) == .changeVisualSelection)
    #expect(engine.mode == .insert)
  }
}
