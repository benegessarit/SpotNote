import Testing

@testable import Spotlight

@Suite("Vim flash labels")
struct VimFlashLabelTests {
  @Test("labels use lowercase then uppercase singles within the single-character alphabet")
  func usesLowercaseThenUppercaseSingles() {
    let text = Array(repeating: "a", count: 52).joined(separator: " ")
    let targets = VimFlash.targets(
      in: text,
      from: 0,
      request: VimFlashRequest(query: "a", direction: .forward, count: 1)
    )

    #expect(targets.count == 52)
    #expect(targets.allSatisfy { $0.label.count == 1 })
    #expect(targets[25].label == "m")
    #expect(targets[26].label == "A")
    #expect(targets[51].label == "M")
  }

  @Test("labels stay prefix-free: uniform two-character labels once targets exceed the alphabet")
  func usesUniformTwoCharacterLabelsBeyondTheAlphabet() {
    let text = Array(repeating: "a", count: 56).joined(separator: " ")
    let targets = VimFlash.targets(
      in: text,
      from: 0,
      request: VimFlashRequest(query: "a", direction: .forward, count: 1)
    )

    // With more targets than single-char labels, every label must be two
    // characters; a single-char label would shadow any two-char label that
    // begins with it, making the latter unreachable.
    #expect(targets.count == 56)
    #expect(targets.allSatisfy { $0.label.count == 2 })
    #expect(targets[0].label == "aa")
    #expect(targets[1].label == "as")
  }
}
