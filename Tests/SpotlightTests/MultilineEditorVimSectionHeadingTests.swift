import AppKit
import Testing

@testable import Spotlight

@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  @Test("gT recognizes an uppercase TRAY heading")
  func gShiftTRecognizesUppercaseTrayHeading() {
    let textView = makeVimMotionTextView(text: "Tasks\n## TRAY\nfirst\nsecond")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "T", ignoring: "t", keyCode: 17, modifiers: .shift))

    #expect(textView.string == "Tasks\n## TRAY\nfirst\nsecond\n- ")
    #expect(textView.selectedRange.location == (textView.string as NSString).length)
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("gD recognizes uppercase TODO and TRAY headings")
  func gShiftDRecognizesUppercaseToDoAndTrayHeadings() {
    let textView = makeVimMotionTextView(text: "## TODO\n- email\n- cure\n## TRAY\nrandom")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "D", ignoring: "d", keyCode: 2, modifiers: .shift))

    #expect(textView.string == "## TODO\n- email\n- cure\n- \n## TRAY\nrandom")
    #expect(textView.selectedRange.location == ("## TODO\n- email\n- cure\n- " as NSString).length)
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("gH creates HABITS above an existing Tray section")
  func gShiftHCreatesHabitsAboveTray() {
    let textView = makeVimMotionTextView(text: "- email\n- cure\n\n## Tray\nrandom")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "H", ignoring: "h", keyCode: 4, modifiers: .shift))

    #expect(textView.string == "## Habits\n- email\n- cure\n- \n## Tray\nrandom")
    #expect(textView.selectedRange.location == ("## Habits\n- email\n- cure\n- " as NSString).length)
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("gD finds an existing single-hash # TODO heading instead of duplicating it")
  func gShiftDFindsSingleHashTodoHeading() {
    let textView = makeVimMotionTextView(text: "## HABITS\n- a\n# TODO\n- x\n\n## TRAY")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "D", ignoring: "d", keyCode: 2, modifiers: .shift))

    #expect(textView.string == "## HABITS\n- a\n# TODO\n- x\n- \n## TRAY")
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("gD creates a TODO section between HABITS and TRAY")
  func gShiftDCreatesTodoBetweenHabitsAndTray() {
    let textView = makeVimMotionTextView(text: "## Habits\n- a\n## Tray\nx")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "D", ignoring: "d", keyCode: 2, modifiers: .shift))

    #expect(textView.string == "## Habits\n- a\n## Todo\n- \n## Tray\nx")
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("gH creates Habits just below an existing Big Things section, not above it")
  func gShiftHCreatesHabitsBelowBigThings() {
    let textView = makeVimMotionTextView(text: "## Big Things\n- launch\n## Tray\nx")
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "g", ignoring: "g", keyCode: 5))
    textView.keyDown(with: keyEvent(characters: "H", ignoring: "h", keyCode: 4, modifiers: .shift))

    #expect(textView.string == "## Big Things\n- launch\n## Habits\n- \n## Tray\nx")
    #expect(textView.vimEngine?.mode == .insert)
  }
}
