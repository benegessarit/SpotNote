import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Icon-only checklist editor motions")
struct ChecklistMarkerMotionTests {
  @Test("0 and ^ on a checklist line stop at the visible text start")
  func lineStartMotionsUseVisibleTextStart() {
    let textView = makeChecklistMotionTextView(
      text: "Pick AirBnb",
      checklistLines: [0: .unchecked]
    )
    textView.setSelectedRange(NSRange(location: ("Pick" as NSString).length, length: 0))

    textView.executeMotion(.lineStart)
    #expect(textView.selectedRange.location == 0)

    textView.setSelectedRange(NSRange(location: ("Pick" as NSString).length, length: 0))
    textView.executeMotion(.firstNonBlank)
    #expect(textView.selectedRange.location == 0)
  }

  @Test("h at a checklist visible start stays on the first character")
  func leftAtChecklistStartClamps() {
    let textView = makeNormalModeChecklistMotionTextView(
      text: "Pick AirBnb",
      checklistLines: [0: .unchecked]
    )
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "h", ignoring: "h", keyCode: 4))

    assertCursorDrawsAt(textView, location: 0)
  }

  @Test("normal-mode h from the Pick line visible start does not jump to that line end")
  func hKeyDownFromPickVisibleStartStaysPut() {
    let text = [
      "Pass email for Cure51",
      "Pick AirBnb for Hilary trip",
      "Call Justin re: Allium"
    ].joined(separator: "\n")
    let textView = makeNormalModeChecklistMotionTextView(
      text: text,
      checklistLines: [0: .unchecked, 1: .unchecked, 2: .unchecked]
    )
    let pickLineStart = ("Pass email for Cure51\n" as NSString).length
    textView.setSelectedRange(NSRange(location: pickLineStart, length: 0))

    textView.keyDown(with: keyEvent(characters: "h", ignoring: "h", keyCode: 4))

    assertCursorDrawsAt(textView, location: pickLineStart)
  }

  @Test("counted h at a checklist visible start clamps")
  func countedLeftAtChecklistStartClamps() {
    let textView = makeNormalModeChecklistMotionTextView(
      text: "Pick AirBnb",
      checklistLines: [0: .unchecked]
    )
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "9", ignoring: "9", keyCode: 25))
    textView.keyDown(with: keyEvent(characters: "h", ignoring: "h", keyCode: 4))

    assertCursorDrawsAt(textView, location: 0)
  }

  @Test("k to a checklist line lands on its visible text")
  func upToChecklistLineDrawsAtVisibleLineStart() {
    let text = "Call Justin re: Allium\n3 prospects"
    let textView = makeNormalModeChecklistMotionTextView(
      text: text,
      checklistLines: [0: .unchecked]
    )
    let plainLineStart = ("Call Justin re: Allium\n" as NSString).length
    textView.setSelectedRange(NSRange(location: plainLineStart, length: 0))

    textView.keyDown(with: keyEvent(characters: "k", ignoring: "k", keyCode: 40))

    assertCursorDrawsAt(textView, location: 0)
  }

  @Test("0 after k on a checklist line redraws at the visible text start")
  func zeroAfterKToChecklistLineStaysAtVisibleTextStart() {
    let text = "Write pass email for Cure51\n3 prospects"
    let textView = makeNormalModeChecklistMotionTextView(
      text: text,
      checklistLines: [0: .unchecked]
    )
    let plainLineStart = ("Write pass email for Cure51\n" as NSString).length
    textView.setSelectedRange(NSRange(location: plainLineStart, length: 0))

    textView.keyDown(with: keyEvent(characters: "k", ignoring: "k", keyCode: 40))
    textView.keyDown(with: keyEvent(characters: "0", ignoring: "0", keyCode: 29))

    assertCursorDrawsAt(textView, location: 0)
  }

  @Test("plain-line h at line start does not wrap to the previous line end")
  func leftAtPlainLineStartDoesNotWrap() {
    let textView = makeNormalModeChecklistMotionTextView(
      text: "alpha\nPick AirBnb",
      checklistLines: [1: .unchecked]
    )
    let pickLineStart = ("alpha\n" as NSString).length
    textView.setSelectedRange(NSRange(location: pickLineStart, length: 0))

    textView.keyDown(with: keyEvent(characters: "h", ignoring: "h", keyCode: 4))

    assertCursorDrawsAt(textView, location: pickLineStart)
  }

  private func makeChecklistMotionTextView(
    text: String,
    checklistLines: [Int: ChecklistLineState]
  ) -> PlaceholderTextView {
    let textView = PlaceholderTextView(
      frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 240)
    )
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text
    textView.checklistLines = checklistLines
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

  private func makeNormalModeChecklistMotionTextView(
    text: String,
    checklistLines: [Int: ChecklistLineState]
  ) -> PlaceholderTextView {
    let textView = makeChecklistMotionTextView(text: text, checklistLines: checklistLines)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    return textView
  }

  private func expectedCharacterMinX(
    in textView: PlaceholderTextView,
    at location: Int
  ) -> CGFloat {
    guard let layoutManager = textView.layoutManager,
      let container = textView.textContainer
    else { return 0 }
    layoutManager.ensureLayout(for: container)
    let glyph = layoutManager.glyphIndexForCharacter(at: location)
    return textView.textContainerOrigin.x
      + layoutManager.boundingRect(
        forGlyphRange: NSRange(location: glyph, length: 1),
        in: container
      ).minX
  }

  private func assertCursorDrawsAt(_ textView: PlaceholderTextView, location: Int) {
    let actualRect = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )
    #expect(textView.selectedRange.location == location)
    #expect(abs(actualRect.minX - expectedCharacterMinX(in: textView, at: location)) < 0.5)
  }

  private func keyEvent(characters: String, ignoring: String, keyCode: UInt16) -> NSEvent {
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
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
