import AppKit
import Testing

@testable import Spotlight

@Suite("EditorMetrics")
struct EditorMetricsTests {
  @Test("empty string is one logical line")
  func emptyIsOneLine() {
    #expect(EditorMetrics.lineCount(in: "") == 1)
  }

  @Test("single line with no newline is one line")
  func singleLine() {
    #expect(EditorMetrics.lineCount(in: "hello") == 1)
  }

  @Test("n newlines produce n+1 logical lines")
  func newlineCount() {
    #expect(EditorMetrics.lineCount(in: "a\nb") == 2)
    #expect(EditorMetrics.lineCount(in: "a\nb\nc") == 3)
    #expect(EditorMetrics.lineCount(in: "a\nb\nc\nd") == 4)
  }

  @Test("trailing newline counts as starting a new line")
  func trailingNewline() {
    #expect(EditorMetrics.lineCount(in: "a\n") == 2)
  }

  @Test("panelHeight stays roomy for short notes before growing")
  func panelHeightRoomyFloorThenGrows() {
    let one = EditorMetrics.panelHeight(forLines: 1, maxLines: 3)
    let two = EditorMetrics.panelHeight(forLines: 2, maxLines: 3)
    let three = EditorMetrics.panelHeight(forLines: 3, maxLines: 3)
    #expect(one == three)
    #expect(two == three)
  }

  @Test("panelHeight clamps at the supplied maxLines")
  func panelHeightClamps() {
    let three = EditorMetrics.panelHeight(forLines: 3, maxLines: 3)
    let seven = EditorMetrics.panelHeight(forLines: 7, maxLines: 3)
    let hundred = EditorMetrics.panelHeight(forLines: 100, maxLines: 3)
    #expect(three == seven)
    #expect(three == hundred)
  }

  @Test("panelHeight honors a smaller user cap")
  func panelHeightHonorsSmallMax() {
    let one = EditorMetrics.panelHeight(forLines: 1, maxLines: 3)
    let three = EditorMetrics.panelHeight(forLines: 3, maxLines: 3)
    let seven = EditorMetrics.panelHeight(forLines: 7, maxLines: 3)
    #expect(one == three)
    #expect(three == seven)
  }

  @Test("panelHeight grows with a larger maxLines")
  func panelHeightHonoursLargerMax() {
    let capped = EditorMetrics.panelHeight(forLines: 10, maxLines: 3)
    let expanded = EditorMetrics.panelHeight(forLines: 10, maxLines: 10)
    let wayBigger = EditorMetrics.panelHeight(forLines: 10, maxLines: 30)
    #expect(expanded > capped)
    #expect(wayBigger == expanded, "row-count hits the ceiling at 10 when maxLines >= 10")
  }

  @Test("panelHeight treats zero and negative line counts as one line")
  func panelHeightFloor() {
    let one = EditorMetrics.panelHeight(forLines: 1, maxLines: 3)
    #expect(EditorMetrics.panelHeight(forLines: 0, maxLines: 3) == one)
    #expect(EditorMetrics.panelHeight(forLines: -3, maxLines: 3) == one)
  }

  @Test("panelHeight treats zero maxLines as one line")
  func panelHeightMaxFloor() {
    let one = EditorMetrics.panelHeight(forLines: 5, maxLines: 1)
    #expect(EditorMetrics.panelHeight(forLines: 5, maxLines: 0) == one)
    #expect(EditorMetrics.panelHeight(forLines: 5, maxLines: -7) == one)
  }

  @Test("editor metrics use the slightly smaller nvim-style HUD scale")
  func slightlySmallerNvimStyleScale() {
    #expect(EditorMetrics.fontSize == 22)
    #expect(EditorMetrics.lineHeight >= 34)
    #expect(EditorMetrics.panelWidth >= 720)
  }

  @Test("short notes open at roughly twice the old four-line HUD height")
  func shortNotesOpenAtDoubleHeight() {
    let oldFourLineHeight =
      CGFloat(4) * EditorMetrics.lineHeight
      + EditorMetrics.verticalInset * 2
      + EditorMetrics.outerPadding * 2
    let openHeight = EditorMetrics.panelHeight(forLines: 4, maxLines: 10)

    #expect(EditorMetrics.roomyVisibleLinesFloor == 9)
    #expect(openHeight == EditorMetrics.panelHeight(forLines: 9, maxLines: 10))
    #expect(openHeight >= oldFourLineHeight * 1.95)
  }

  @Test("task editor keeps restored breathing room before text")
  @MainActor
  func taskEditorKeepsRestoredLeadingTextGap() {
    #expect(EditorMetrics.leadingInset == 0)
    #expect(LineNumberRuler.markerOnlyThickness(forLabelSize: LineNumberRuler.labelFontSize) == 0)
    #expect(EditorMetrics.textLeadingGap >= 32)
  }

  @Test("editor leaves only a narrow right inset so the scrollbar hugs the card edge")
  func narrowRightInsetForEdgeScroller() {
    #expect(EditorMetrics.trailingInset <= 8)
  }

  @Test("normal-mode cursor matches the Mirage block metrics")
  @MainActor
  func normalModeCursorMatchesMirageBlock() throws {
    #expect(EditorMetrics.normalModeCursorWidth >= 12)
    let color = try #require(
      PlaceholderTextView.normalModeCursorColor.usingColorSpace(NSColorSpace.sRGB)
    )
    #expect(abs(color.redComponent - (221 / 255)) < 0.01)
    #expect(abs(color.greenComponent - (179 / 255)) < 0.01)
    #expect(abs(color.blueComponent - 1.0) < 0.01)
  }
}
