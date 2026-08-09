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

  // MARK: - thickness

  @Test("flash-hint labels use the same scale as editor text")
  func labelFontUsesEditorScale() {
    #expect(LineNumberRuler.labelFontSize == EditorMetrics.fontSize)
  }

  @Test("the gutter is zero-width whenever line-flash hints are not showing")
  func gutterCollapsesWithoutFlashHints() {
    #expect(LineNumberRuler.thickness(showsLineFlashHints: false, labelSize: 15) == 0)
    #expect(LineNumberRuler.thickness(showsLineFlashHints: false, labelSize: 22) == 0)
    #expect(LineNumberRuler.thickness(showsLineFlashHints: false, labelSize: 30) == 0)
  }

  @Test("line Flash temporarily opens the hidden gutter for row labels")
  func lineFlashTemporarilyOpensHiddenGutter() {
    let open = LineNumberRuler.thickness(showsLineFlashHints: true, labelSize: 22)
    #expect(open > 0)
    #expect(open == LineNumberRuler.signColumnWidth(forLabelSize: 22))
  }

  @Test("flash gutter fits a bold two-character label")
  func flashGutterFitsTwoCharacterLabel() {
    let labelSize: CGFloat = 22
    let font = NSFont.boldSystemFont(ofSize: labelSize)
    let labelWidth = ("aa" as NSString).size(withAttributes: [.font: font]).width
    #expect(LineNumberRuler.signColumnWidth(forLabelSize: labelSize) >= ceil(labelWidth))
  }

  @Test("Markdown checklist parse distinguishes open and completed states")
  func markdownChecklistParseDistinguishesStates() {
    let document = ChecklistDocument.parseMarkdown("[   ] open\n[ x ] done")

    #expect(document.text == "open\ndone")
    #expect(document.checklistLines == [0: .unchecked, 1: .checked])
  }

}
