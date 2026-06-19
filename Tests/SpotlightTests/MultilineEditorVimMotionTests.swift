// swiftlint:disable type_body_length
import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor vim logical line motions")
struct MultilineEditorVimLogicalLineMotionTests {
  @Test("j steps one logical line at a time over icon-only checklist lines")
  func downOverChecklistMarkers() {
    let textView = makeVimMotionTextView(
      text: "plain\none\ntwo\nthree\nafter",
      checklistLines: [1: .unchecked, 2: .unchecked, 3: .checked]
    )
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.executeMotion(.down(1))
    #expect(textView.selectedRange.location == ("plain\n" as NSString).length)

    textView.executeMotion(.down(1))
    #expect(textView.selectedRange.location == ("plain\none\n" as NSString).length)
  }

  @Test("gg scrolls the document start to the top of a long visible note")
  func ggScrollsDocumentStartToTop() {
    let text = (0..<30).map { "line \($0)" }.joined(separator: "\n")
    let textView = makeScrollableVimMotionTextView(text: text)
    let scrollView = makeScrollView(containing: textView)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: EditorMetrics.lineHeight * 6))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))

    #expect(textView.selectedRange.location == 0)
    #expect(scrollView.contentView.documentVisibleRect.minY == 0)
  }

  @Test("G scrolls the document end to the bottom of a long visible note")
  func shiftGScrollsDocumentEndToBottom() {
    let text = (0..<30).map { "line \($0)" }.joined(separator: "\n")
    let textView = makeScrollableVimMotionTextView(text: text)
    let scrollView = makeScrollView(containing: textView)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    scrollView.contentView.scroll(to: .zero)
    scrollView.reflectScrolledClipView(scrollView.contentView)

    textView.keyDown(with: keyEvent(characters: "G", ignoring: "g", keyCode: 5, modifiers: .shift))

    let documentBottomY = scrollView.contentView.documentRect.maxY
    let visibleBottomY = scrollView.contentView.documentVisibleRect.maxY
    #expect(textView.selectedRange.location == (text as NSString).length)
    #expect(abs(visibleBottomY - documentBottomY) < 0.001)
  }

  @Test("j preserves the column across icon-only checklist lines")
  func downPreservesVisibleColumnAcrossChecklistMarkers() {
    let textView = makeVimMotionTextView(
      text: "plain\nPick AirBnb\n3 prospects",
      checklistLines: [1: .unchecked]
    )
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.executeMotion(.down(1))
    #expect(textView.selectedRange.location == ("plain\n" as NSString).length)

    textView.executeMotion(.down(1))
    #expect(textView.selectedRange.location == ("plain\nPick AirBnb\n" as NSString).length)
  }

  @Test("k preserves the column across icon-only checklist lines")
  func upPreservesVisibleColumnAcrossChecklistMarkers() {
    let text = "Pick AirBnb\n3 prospects"
    let textView = makeVimMotionTextView(text: text, checklistLines: [0: .unchecked])
    textView.setSelectedRange(NSRange(location: ("Pick AirBnb\n" as NSString).length, length: 0))

    textView.executeMotion(.up(1))
    #expect(textView.selectedRange.location == 0)
  }

  @Test("j and k step through fenced code block lines")
  func verticalMotionsOverFencedCodeBlock() {
    let textView = makeVimMotionTextView(text: "before\n```swift\nlet x = 1\nlet y = 2\n```\nafter")
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.executeMotion(.down(3))
    #expect(textView.selectedRange.location == ("before\n```swift\nlet x = 1\n" as NSString).length)

    textView.executeMotion(.up(1))
    #expect(textView.selectedRange.location == ("before\n```swift\n" as NSString).length)
  }

  @Test("normal mode caret at code block line start uses that line fragment")
  func lineStartCaretRectInsideCodeBlock() {
    let textView = makeVimMotionTextView(text: "before\n```cpp\nint x;\nint y;\n```\nafter")
    let lineStart = ("before\n```cpp\n" as NSString).length
    textView.setSelectedRange(NSRange(location: lineStart, length: 0))

    let rect = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )

    #expect(rect.origin.y == EditorMetrics.lineHeight * 2)
  }

  @Test("insert caret at closing fence end keeps the fence column")
  func closingFenceEndCaretRectKeepsXPosition() {
    let textView = makeVimMotionTextView(text: "before\n```cpp\nint x;\n```\nafter")
    let fenceEnd = ("before\n```cpp\nint x;\n```" as NSString).length
    textView.setSelectedRange(NSRange(location: fenceEnd, length: 0))

    let rect = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )

    #expect(rect.origin.y == EditorMetrics.lineHeight * 3)
    #expect(rect.origin.x > 1)
  }

  @Test("trailing newline caret still uses the extra line fragment")
  func trailingNewlineCaretRectUsesExtraLineFragment() {
    let textView = makeVimMotionTextView(text: "before\n")
    textView.setSelectedRange(NSRange(location: ("before\n" as NSString).length, length: 0))

    let rect = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )

    #expect(rect.origin.y == EditorMetrics.lineHeight)
  }

  @Test("gT jumps to the next open line at the end of an existing Tray section")
  func gShiftTJumpsToExistingTrayOpenLine() {
    let textView = makeVimMotionTextView(text: "Tasks\n## Tray\nfirst\nsecond")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "T", ignoring: "t", keyCode: 17, modifiers: .shift))

    #expect(textView.string == "Tasks\n## Tray\nfirst\nsecond\n")
    #expect(textView.selectedRange.location == (textView.string as NSString).length)
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("gT ignores internal Tray blank lines and appends after the last Tray item")
  func gShiftTIgnoresInternalTrayBlankLines() {
    let textView = makeVimMotionTextView(text: "Tasks\n## Tray\nfirst\n\nsecond\n\nthird")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "T", ignoring: "t", keyCode: 17, modifiers: .shift))

    #expect(textView.string == "Tasks\n## Tray\nfirst\n\nsecond\n\nthird\n")
    #expect(textView.selectedRange.location == (textView.string as NSString).length)
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("gT creates a missing Tray section at the bottom and enters insert mode")
  func gShiftTCreatesMissingTraySection() {
    let textView = makeVimMotionTextView(text: "Tasks\nalpha")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "T", ignoring: "t", keyCode: 17, modifiers: .shift))

    #expect(textView.string == "Tasks\nalpha\n\n## Tray\n")
    #expect(textView.selectedRange.location == (textView.string as NSString).length)
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("gD jumps to a new To Do bullet line before Tray")
  func gShiftDJumpsToNewToDoBulletBeforeTray() {
    let textView = makeVimMotionTextView(text: "## To Do\n- email\n- cure\n## Tray\nrandom")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "D", ignoring: "d", keyCode: 2, modifiers: .shift))

    #expect(textView.string == "## To Do\n- email\n- cure\n- \n## Tray\nrandom")
    #expect(textView.selectedRange.location == ("## To Do\n- email\n- cure\n- " as NSString).length)
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("gD creates To Do above an existing Tray section")
  func gShiftDCreatesToDoAboveTray() {
    let textView = makeVimMotionTextView(text: "- email\n- cure\n\n## Tray\nrandom")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "D", ignoring: "d", keyCode: 2, modifiers: .shift))

    #expect(textView.string == "## To Do\n- email\n- cure\n- \n## Tray\nrandom")
    #expect(textView.selectedRange.location == ("## To Do\n- email\n- cure\n- " as NSString).length)
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("normal-mode block cursor paints only while AppKit blink is on")
  func normalModeCursorRespectsBlinkState() throws {
    let textView = makeVimMotionTextView(text: "alpha")
    textView.vimModeEnabled = true
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    let onRep = try makeBitmapRep()
    drawCursor(
      for: textView,
      in: NSRect(x: 4, y: 0, width: 1, height: EditorMetrics.lineHeight),
      turnedOn: true,
      rep: onRep
    )
    #expect(bitmapContainsMirageCursor(onRep))

    let offRep = try makeBitmapRep()
    drawCursor(
      for: textView,
      in: NSRect(x: 4, y: 0, width: 1, height: EditorMetrics.lineHeight),
      turnedOn: false,
      rep: offRep
    )
    #expect(!bitmapContainsMirageCursor(offRep))
  }

  @Test("Flash jump moves to the first whole-document matching character")
  func flashJumpForward() {
    let textView = makeVimMotionTextView(text: "alpha beta gamma")
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    let jumped = textView.performFlashJump(VimFlashRequest(query: "a", direction: .forward, count: 1))

    #expect(jumped)
    #expect(textView.selectedRange.location == 0)
  }

  @Test("Flash jump can search backward from the end of the document")
  func flashJumpBackward() {
    let textView = makeVimMotionTextView(text: "alpha beta gamma")
    textView.setSelectedRange(NSRange(location: ("alpha beta gam" as NSString).length, length: 0))

    let jumped = textView.performFlashJump(VimFlashRequest(query: "a", direction: .backward, count: 2))

    #expect(jumped)
    #expect(textView.selectedRange.location == ("alpha beta g" as NSString).length)
  }

  @Test("Flash jump reports no match without moving the caret")
  func flashJumpNoMatch() {
    let textView = makeVimMotionTextView(text: "alpha beta")
    textView.setSelectedRange(NSRange(location: 3, length: 0))

    let jumped = textView.performFlashJump(VimFlashRequest(query: "z", direction: .forward, count: 1))

    #expect(!jumped)
    #expect(textView.selectedRange.location == 3)
  }

  @Test("Flash jump matches only composed-character boundaries")
  func flashJumpUsesComposedCharacterBoundaries() {
    let text = "x e\u{301} y"

    let accentOnly = VimFlash.targetLocation(
      in: text,
      from: 0,
      request: VimFlashRequest(query: "\u{301}", direction: .forward, count: 1)
    )
    let composed = VimFlash.targetLocation(
      in: text,
      from: 0,
      request: VimFlashRequest(query: "é", direction: .forward, count: 1)
    )

    #expect(accentOnly == nil)
    #expect(composed == ("x " as NSString).length)
  }

  @Test("Flash targets include stable labels for whole-document visible hints")
  func flashTargetsHaveLabels() {
    let targets = VimFlash.targets(
      in: "alpha beta gamma",
      from: ("alpha bet" as NSString).length,
      request: VimFlashRequest(query: "a", direction: .forward, count: 1)
    )

    #expect(targets.map(\.location) == [0, 4, 9, 12, 15])
    #expect(targets.map(\.label) == ["a", "s", "d", "f", "g"])
  }

  @Test("Flash search ignores capitalization")
  func flashSearchIgnoresCapitalization() {
    let targets = VimFlash.targets(
      in: "Alpha alpha ALPHA",
      from: 0,
      request: VimFlashRequest(query: "al", direction: .forward, count: 1)
    )

    #expect(targets.map(\.location) == [0, 6, 12])
  }

  @Test("backward whole-document Flash labels targets from the end of the document")
  func flashBackwardDocumentTargetsReverseOrder() {
    let targets = VimFlash.targets(
      in: "alpha beta gamma",
      from: 0,
      request: VimFlashRequest(query: "a", direction: .backward, count: 1)
    )

    #expect(targets.map(\.location) == [15, 12, 9, 4, 0])
    #expect(targets.map(\.label) == ["a", "s", "d", "f", "g"])
  }

  @Test("same-line Flash targets stay on the current line")
  func flashSameLineTargetsOnlyCurrentLine() {
    let text = "alpha arc\nbeta alpha\ncarrot alarm"
    let secondLineStart = ("alpha arc\n" as NSString).length
    let targets = VimFlash.targets(
      in: text,
      from: secondLineStart,
      request: VimFlashRequest(query: "a", direction: .forward, count: 1, scope: .currentLine)
    )

    #expect(targets.map(\.location) == [secondLineStart + 3, secondLineStart + 5, secondLineStart + 9])
  }

  @Test("same-line backward Flash targets stay before the caret on the current line")
  func flashSameLineBackwardTargetsOnlyCurrentLineBeforeCaret() {
    let text = "alpha arc\nbeta alpha\ncarrot alarm"
    let secondLineStart = ("alpha arc\n" as NSString).length
    let secondLineEnd = secondLineStart + ("beta alpha" as NSString).length
    let targets = VimFlash.targets(
      in: text,
      from: secondLineEnd,
      request: VimFlashRequest(query: "a", direction: .backward, count: 1, scope: .currentLine)
    )

    #expect(targets.map(\.location) == [secondLineStart + 9, secondLineStart + 5, secondLineStart + 3])
  }

  @Test("Flash row targets label logical line starts")
  func flashLineTargetsLabelRows() {
    let targets = VimFlash.lineTargets(in: "one\ntwo\nthree", from: 0)

    #expect(targets.map(\.location) == [0, 4, 8])
    #expect(targets.map(\.label) == ["a", "s", "d"])
  }

  @Test("Flash target labels use lowercase then uppercase singles before two-character fallback")
  func flashTargetsUseUppercaseSinglesBeforeTwoCharacterLabels() {
    let text = Array(repeating: "a", count: 56).joined(separator: " ")
    let targets = VimFlash.targets(
      in: text,
      from: 0,
      request: VimFlashRequest(query: "a", direction: .forward, count: 1)
    )

    #expect(targets.count == 56)
    #expect(targets.prefix(52).allSatisfy { $0.label.count == 1 })
    #expect(targets[25].label == "m")
    #expect(targets[26].label == "A")
    #expect(targets[51].label == "M")
    #expect(targets[52].label == "aa")
  }

  @Test("Flash row targets follow visible display rows including soft wraps")
  func flashLineTargetsUseVisibleDisplayRows() {
    let text = "alpha beta gamma delta epsilon\nsecond"
    let textView = makeVimMotionTextView(text: text, width: 120)

    let targets = textView.visibleLineFlashTargets(limit: 10)

    #expect(targets.count > 2)
    #expect(targets[0].location == 0)
    #expect(targets[1].location > 0)
    #expect(targets[1].location < ("alpha beta gamma delta epsilon\n" as NSString).length)
    #expect(targets.contains { $0.location == ("alpha beta gamma delta epsilon\n" as NSString).length })
  }

  @Test("Shift-K keyDown opens visible row Flash labels")
  func shiftKKeyDownOpensLineFlash() {
    let textView = makeVimMotionTextView(text: "one\ntwo\nthree")
    let controller = VimController()
    textView.attachVimController(controller)
    textView.vimModeEnabled = true

    textView.keyDown(with: keyEvent(characters: "K", ignoring: "k", keyCode: 40, modifiers: .shift))

    #expect(controller.prompt?.kind == .lineFlash(count: 1))
    #expect(textView.isShowingLineFlashHints)
    #expect(Array(textView.flashHints.map(\.label).prefix(3)) == ["a", "s", "d"])
  }

  @Test("f keyDown opens same-line Flash labels only on the current line")
  func fKeyDownOpensSameLineFlash() {
    let text = "alpha arc\nbeta alpha\ncarrot alarm"
    let textView = makeVimMotionTextView(text: text)
    let controller = VimController()
    textView.attachVimController(controller)
    textView.vimModeEnabled = true
    let secondLineStart = ("alpha arc\n" as NSString).length
    textView.setSelectedRange(NSRange(location: secondLineStart, length: 0))

    textView.keyDown(with: keyEvent(characters: "f", ignoring: "f", keyCode: 3))
    textView.keyDown(with: keyEvent(characters: "a", ignoring: "a", keyCode: 0))

    #expect(controller.prompt?.kind == .flash(.forward, count: 1, scope: .currentLine))
    #expect(textView.flashHints.map(\.location) == [secondLineStart + 3, secondLineStart + 5, secondLineStart + 9])
  }

  @Test("s keyDown starts a dimmed Flash prompt without entering s into the query")
  func flashTriggerStartsEmptyDimmedPrompt() {
    let textView = makeVimMotionTextView(text: "alpha beta gamma")
    let controller = VimController()
    textView.attachVimController(controller)
    textView.vimModeEnabled = true

    textView.keyDown(with: keyEvent(characters: "s", ignoring: "s", keyCode: 1))

    #expect(controller.prompt?.buffer.isEmpty == true)
    #expect(textView.flashHints.isEmpty)
    #expect(temporaryForegroundColor(at: 0, in: textView) != nil)
  }

  @Test("regular Flash colors typed query characters before showing labels")
  func flashQueryColorsMatchesBeforeLabels() {
    let textView = makeVimMotionTextView(text: "x not now notion")
    let controller = VimController()
    textView.attachVimController(controller)
    textView.vimModeEnabled = true
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "s", ignoring: "s", keyCode: 1))
    textView.keyDown(with: keyEvent(characters: "n", ignoring: "n", keyCode: 45))

    let firstTargetLocation = ("x " as NSString).length
    #expect(textView.flashHints.first?.location == firstTargetLocation)
    #expect(
      colorComponents(temporaryForegroundColor(at: firstTargetLocation, in: textView))
        != colorComponents(temporaryForegroundColor(at: 0, in: textView))
    )
    #expect((temporaryForegroundColor(at: firstTargetLocation + 1, in: textView)?.alphaComponent ?? 1) > 0.01)
  }

  @Test("regular Flash labels replace the next target word characters in place")
  func flashLabelsHideReplacementCharactersInPlace() {
    let textView = makeVimMotionTextView(text: "x not now notion")
    let controller = VimController()
    textView.attachVimController(controller)
    textView.vimModeEnabled = true
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "s", ignoring: "s", keyCode: 1))
    textView.keyDown(with: keyEvent(characters: "n", ignoring: "n", keyCode: 45))
    textView.keyDown(with: keyEvent(characters: "o", ignoring: "o", keyCode: 31))

    let firstTargetLocation = ("x " as NSString).length
    let replacementLocation = firstTargetLocation + ("no" as NSString).length
    #expect(textView.flashHints.first?.label == "a")
    #expect(temporaryForegroundColor(at: replacementLocation, in: textView)?.alphaComponent == 0)
  }

  @Test("s query plus visible label keyDown jumps and clears Flash")
  func flashKeyDownQueryAndLabelJumps() {
    let textView = makeVimMotionTextView(text: "zero alpha beta alpha")
    let controller = VimController()
    textView.attachVimController(controller)
    textView.vimModeEnabled = true
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "s", ignoring: "s", keyCode: 1))
    textView.keyDown(with: keyEvent(characters: "a", ignoring: "a", keyCode: 0))
    textView.keyDown(with: keyEvent(characters: "l", ignoring: "l", keyCode: 37))
    let firstTarget = textView.flashHints[0]
    textView.keyDown(with: keyEvent(characters: firstTarget.label, ignoring: firstTarget.label, keyCode: 0))

    #expect(controller.prompt == nil)
    #expect(textView.flashHints.isEmpty)
    #expect(textView.selectedRange.location == firstTarget.location)
    #expect(temporaryForegroundColor(at: firstTarget.location, in: textView) == nil)
  }

}
