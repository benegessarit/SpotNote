import AppKit
import Testing

@testable import Spotlight

@Suite("LineNumberRuler")
@MainActor
struct LineNumberRulerTests {
  // MARK: - synthesizedBaseline

  @Test("synthesizedBaseline centers the glyph by splitting extra space equally above and below")
  func extraSpaceSplitEqually() {
    let font = NSFont.systemFont(ofSize: 16)
    let fragmentHeight: CGFloat = 22
    let baseline = LineNumberRuler.synthesizedBaseline(
      fragmentHeight: fragmentHeight,
      font: font
    )
    let fontHeight = font.ascender - font.descender
    // Matches FixedLineHeightLayoutManager.setLocation: ascender + (extra / 2)
    let expected = font.ascender + (fragmentHeight - fontHeight) / 2
    #expect(abs(baseline - expected) < 0.001)
  }

  @Test("synthesizedBaseline with a fragment exactly the font height gives ascender")
  func fragmentEqualsFontHeight() {
    let font = NSFont.systemFont(ofSize: 14)
    let fontHeight = font.ascender - font.descender
    let baseline = LineNumberRuler.synthesizedBaseline(
      fragmentHeight: fontHeight,
      font: font
    )
    #expect(abs(baseline - font.ascender) < 0.001)
  }

  @Test("synthesizedBaseline does not go negative when the fragment is smaller than the font")
  func clampsWhenFragmentIsSmall() {
    let font = NSFont.systemFont(ofSize: 16)
    let baseline = LineNumberRuler.synthesizedBaseline(fragmentHeight: 5, font: font)
    // With the clamp, extra-space is 0, so baseline == ascender.
    #expect(abs(baseline - font.ascender) < 0.001)
  }

  @Test("synthesizedBaseline grows 0.5:1 with fragment height beyond the font height")
  func baselineGrowsWithFragment() {
    let font = NSFont.systemFont(ofSize: 16)
    let small = LineNumberRuler.synthesizedBaseline(fragmentHeight: 22, font: font)
    let large = LineNumberRuler.synthesizedBaseline(fragmentHeight: 32, font: font)
    // Centering: 10pt of extra fragment height adds 5pt to the baseline
    // (half the extra space goes above, half below).
    #expect(abs((large - small) - 5) < 0.001)
  }

  // MARK: - thickness(forLineCount:labelSize:)

  @Test("line number labels use the same nvim-size scale as editor text")
  func labelFontUsesEditorScale() {
    #expect(LineNumberRuler.labelFontSize == EditorMetrics.fontSize)
  }

  @Test("line number gutter labels stay faded behind the text")
  func gutterLabelsStayFadedBehindText() {
    #expect(LineNumberRuler.defaultTextAlpha <= 0.46)
  }

  @Test("marker-only thickness stays stable as line count grows")
  func markerOnlyThicknessIgnoresDigitBuckets() {
    let single = LineNumberRuler.thickness(forLineCount: 1, labelSize: 15)
    let ten = LineNumberRuler.thickness(forLineCount: 10, labelSize: 15)
    let hundred = LineNumberRuler.thickness(forLineCount: 100, labelSize: 15)
    let thousand = LineNumberRuler.thickness(forLineCount: 1000, labelSize: 15)
    #expect(single == ten)
    #expect(ten == hundred)
    #expect(hundred == thousand)
  }

  @Test("numeric thickness remains available when line numbers are explicitly shown")
  func numericThicknessMonotonic() {
    let single = LineNumberRuler.thickness(forLineCount: 1, labelSize: 15, showsLineNumbers: true)
    let ten = LineNumberRuler.thickness(forLineCount: 10, labelSize: 15, showsLineNumbers: true)
    let hundred = LineNumberRuler.thickness(forLineCount: 100, labelSize: 15, showsLineNumbers: true)
    let thousand = LineNumberRuler.thickness(forLineCount: 1000, labelSize: 15, showsLineNumbers: true)
    #expect(single < ten)
    #expect(ten < hundred)
    #expect(hundred < thousand)
  }

  @Test("numeric thickness is identical within the same digit bucket")
  func numericThicknessBuckets() {
    let sizes = [1, 5, 9].map {
      LineNumberRuler.thickness(forLineCount: $0, labelSize: 15, showsLineNumbers: true)
    }
    #expect(Set(sizes).count == 1, "all single-digit counts should share a thickness")

    let double = [10, 42, 99].map {
      LineNumberRuler.thickness(forLineCount: $0, labelSize: 15, showsLineNumbers: true)
    }
    #expect(Set(double).count == 1, "all two-digit counts should share a thickness")
  }

  @Test("numeric thickness fits the widest digit at the requested label size")
  func numericThicknessFitsDigit() {
    let labelSize: CGFloat = 15
    let font = NSFont.monospacedDigitSystemFont(ofSize: labelSize, weight: .regular)
    let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
    let thickness = LineNumberRuler.thickness(
      forLineCount: 1,
      labelSize: labelSize,
      showsLineNumbers: true
    )
    #expect(thickness >= ceil(digitWidth))
    // And we add a small breathing-room inset beyond raw digit width.
    #expect(thickness > ceil(digitWidth))
  }

  @Test("marker-only thickness stays zero for every label size")
  func markerOnlyThicknessStaysZeroForEveryLabelSize() {
    let defaultSized = LineNumberRuler.thickness(forLineCount: 10, labelSize: 22)
    let large = LineNumberRuler.thickness(forLineCount: 10, labelSize: 30)
    #expect(defaultSized == 0)
    #expect(large == 0)
  }

  @Test("zero or negative hidden line counts keep the zero-width gutter")
  func hiddenLineNumberThicknessFloor() {
    let zero = LineNumberRuler.thickness(forLineCount: 0, labelSize: 15)
    let negative = LineNumberRuler.thickness(forLineCount: -5, labelSize: 15)
    let one = LineNumberRuler.thickness(forLineCount: 1, labelSize: 15)
    #expect(zero == one)
    #expect(negative == one)
  }

  @Test("hidden-line-number mode reserves no checkbox gutter")
  func hiddenLineNumberModeReservesNoCheckboxGutter() {
    #expect(LineNumberRuler.markerOnlyThickness(forLabelSize: 22) == 0)
    #expect(LineNumberRuler.thickness(forLineCount: 999, labelSize: 22) == 0)
    #expect(LineNumberRuler.thickness(forLineCount: 999, labelSize: 22, showsLineNumbers: true) > 0)
  }

  @Test("glyph fragments after blank lines keep their logical line index")
  func glyphFragmentsAfterBlankLinesKeepLogicalLineIndex() {
    let text = "## To Do\n\nPass email" as NSString
    let taskStart = ("## To Do\n\n" as NSString).length

    #expect(LineNumberRuler.logicalLineIndex(forFragmentStartingAt: 0, in: text) == 0)
    #expect(LineNumberRuler.logicalLineIndex(forFragmentStartingAt: taskStart, in: text) == 2)
  }

  @Test("Markdown checklist parse distinguishes open and completed states")
  func markdownChecklistParseDistinguishesStates() {
    let document = ChecklistDocument.parseMarkdown("[   ] open\n[ x ] done")

    #expect(document.text == "open\ndone")
    #expect(document.checklistLines == [0: .unchecked, 1: .checked])
  }

}
