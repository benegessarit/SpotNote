import Testing

@testable import Spotlight

@Suite("SpotNote formatter (\\f tidy)")
struct SpotNoteFormatterTests {
  @Test("top header gets no blank line above; interior headers get one above and below")
  func headerSpacingAroundTopAndInterior() {
    let input = "## Big Things\n- a\n## Habits\n- b"
    let expected = "## Big Things\n\n- a\n\n## Habits\n\n- b"
    #expect(SpotNoteFormatter.normalize(input) == expected)
  }

  @Test("multiple blank lines around a header collapse to exactly one")
  func collapsesMultipleBlanksAroundHeader() {
    #expect(SpotNoteFormatter.normalize("## H\n\n\n\n- a") == "## H\n\n- a")
    #expect(SpotNoteFormatter.normalize("- a\n\n\n## H\n- b") == "- a\n\n## H\n\n- b")
  }

  @Test("a header with no surrounding blanks gains one above and below")
  func addsMissingBlanksAroundInteriorHeader() {
    #expect(SpotNoteFormatter.normalize("- a\n## H\n- b") == "- a\n\n## H\n\n- b")
  }

  @Test("consecutive headers are separated by exactly one blank line")
  func consecutiveHeaders() {
    #expect(SpotNoteFormatter.normalize("## A\n## B\n- x") == "## A\n\n## B\n\n- x")
  }

  @Test("leading blank lines above the top header are removed")
  func stripsLeadingBlanksAboveTopHeader() {
    #expect(SpotNoteFormatter.normalize("\n\n## H\n- a") == "## H\n\n- a")
  }

  @Test("bullets and multiline bullet bodies are preserved verbatim")
  func preservesBulletsAndMultilineBullets() {
    let input = "## Todo\n- task one\n  continued line\n- task two"
    let expected = "## Todo\n\n- task one\n  continued line\n- task two"
    #expect(SpotNoteFormatter.normalize(input) == expected)
  }

  @Test("blank lines between non-headers are left untouched")
  func leavesNonHeaderBlanksAlone() {
    let input = "- a\n\n- b\n\n\n- c"
    #expect(SpotNoteFormatter.normalize(input) == input)
  }

  @Test("a trailing newline is preserved")
  func preservesTrailingNewline() {
    #expect(SpotNoteFormatter.normalize("## H\n- a\n") == "## H\n\n- a\n")
    #expect(SpotNoteFormatter.normalize("- a\n").hasSuffix("\n"))
    #expect(!SpotNoteFormatter.normalize("- a").hasSuffix("\n"))
  }

  @Test("the transform is idempotent")
  func idempotent() {
    let inputs = [
      "## Big Things\n- a\n## Habits\n- b",
      "\n\n## H\n\n\n- a\n\n## H2\nx",
      "- only bullets\n  continued\n- more"
    ]
    for input in inputs {
      let once = SpotNoteFormatter.normalize(input)
      #expect(SpotNoteFormatter.normalize(once) == once)
    }
  }

  @Test("a #label line is not treated as a header")
  func labelLineIsNotAHeader() {
    #expect(!SpotNoteFormatter.isHeader("#Amplify do the thing"))
    #expect(SpotNoteFormatter.isHeader("# Real heading"))
    #expect(SpotNoteFormatter.isHeader("### Three"))
    #expect(!SpotNoteFormatter.isHeader("- a bullet"))
  }
}
