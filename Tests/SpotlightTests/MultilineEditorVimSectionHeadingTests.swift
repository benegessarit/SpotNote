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
}
