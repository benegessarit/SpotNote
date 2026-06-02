// swiftlint:disable type_body_length
import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor vim logical line motions")
struct MultilineEditorVimLogicalLineMotionTests {
  @Test("j steps one logical line at a time over checklist markers")
  func downOverChecklistMarkers() {
    let textView = makeVimMotionTextView(text: "plain\n☐ one\n☐ two\n☑ three\nafter")
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.executeMotion(.down(1))
    #expect(textView.selectedRange.location == ("plain\n" as NSString).length)

    textView.executeMotion(.down(1))
    #expect(textView.selectedRange.location == ("plain\n☐ one\n" as NSString).length)
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
    #expect(textView.flashHints.map(\.label).prefix(3) == ["a", "s", "d"])
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

  @Test("ciw deletes the word under the caret and leaves insert point at the word start")
  func changeInnerWordDeletesWord() {
    let textView = makeVimMotionTextView(text: "alpha beta gamma")
    textView.setSelectedRange(NSRange(location: ("alpha be" as NSString).length, length: 0))

    textView.executeVimAction(.changeTextObject(.innerWord))

    #expect(textView.string == "alpha  gamma")
    #expect(textView.selectedRange == NSRange(location: ("alpha " as NSString).length, length: 0))
  }

  @Test("semicolon-b wraps the current word in markdown bold markers")
  func semicolonBoldWrapsCurrentWord() {
    let textView = makeVimMotionTextView(text: "alpha beta gamma")
    textView.setSelectedRange(NSRange(location: ("alpha be" as NSString).length, length: 0))

    textView.executeVimAction(.wrapCurrentWord(.bold))

    #expect(textView.string == "alpha **beta** gamma")
    #expect(textView.selectedRange.location == ("alpha **beta**" as NSString).length)
  }

  @Test("semicolon-i wraps the current word in markdown italic markers")
  func semicolonItalicWrapsCurrentWord() {
    let textView = makeVimMotionTextView(text: "alpha beta gamma")
    textView.setSelectedRange(NSRange(location: ("alpha be" as NSString).length, length: 0))

    textView.executeVimAction(.wrapCurrentWord(.italic))

    #expect(textView.string == "alpha *beta* gamma")
    #expect(textView.selectedRange.location == ("alpha *beta*" as NSString).length)
  }

  private func makeVimMotionTextView(
    text: String,
    width: CGFloat = EditorMetrics.panelWidth
  ) -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: width, height: 240))
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    guard let storage = textView.textStorage,
      let container = textView.textContainer
    else { return textView }
    let fixed = FixedLineHeightLayoutManager()
    fixed.fixedLineHeight = EditorMetrics.lineHeight
    fixed.editorFont = textView.font ?? .systemFont(ofSize: EditorMetrics.fontSize)
    if let existing = storage.layoutManagers.first {
      storage.removeLayoutManager(existing)
    }
    storage.addLayoutManager(fixed)
    fixed.addTextContainer(container)
    CodeStyler.apply(to: textView, theme: ThemeCatalog.obsidian)
    return textView
  }

  private func temporaryForegroundColor(at location: Int, in textView: PlaceholderTextView) -> NSColor? {
    textView.layoutManager?.temporaryAttributes(
      atCharacterIndex: location,
      effectiveRange: nil
    )[.foregroundColor] as? NSColor
  }

  private func colorComponents(_ color: NSColor?) -> [CGFloat] {
    guard let color = color?.usingColorSpace(.deviceRGB) else { return [] }
    return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
  }

  private func keyEvent(
    characters: String,
    ignoring: String,
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags = []
  ) -> NSEvent {
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: ignoring,
        isARepeat: false,
        keyCode: keyCode
      )
    else { fatalError("failed to create key event") }
    return event
  }
}
