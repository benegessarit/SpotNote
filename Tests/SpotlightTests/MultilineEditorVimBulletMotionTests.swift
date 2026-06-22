import AppKit
import Testing

@testable import Spotlight

@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  @Test("w from a markdown bullet marker jumps to the first body character")
  func wordForwardFromBulletMarkerJumpsToBodyStart() {
    let text = "- Review pin ai results"
    let textView = makeVimMotionTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "w", ignoring: "w", keyCode: 13))

    #expect(textView.selectedRange.location == ("- " as NSString).length)
  }

  @Test("counted w from a markdown bullet marker counts body start as the first word target")
  func countedWordForwardFromBulletMarkerCountsBodyStart() {
    let text = "- Review pin ai results"
    let textView = makeVimMotionTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "2", ignoring: "2", keyCode: 19))
    textView.keyDown(with: keyEvent(characters: "w", ignoring: "w", keyCode: 13))

    #expect(textView.selectedRange.location == ("- Review " as NSString).length)
  }

  @Test("cib deletes only bullet body and enters insert after the marker")
  func cIBDeletesOnlyBulletBodyAndEntersInsert() {
    let text = "- Review pin ai results\n- Keep second"
    let textView = makeVimMotionTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: ("- Review" as NSString).length, length: 0))

    textView.keyDown(with: keyEvent(characters: "c", ignoring: "c", keyCode: 8))
    textView.keyDown(with: keyEvent(characters: "i", ignoring: "i", keyCode: 34))
    textView.keyDown(with: keyEvent(characters: "b", ignoring: "b", keyCode: 11))

    #expect(textView.string == "- \n- Keep second")
    #expect(textView.selectedRange.location == ("- " as NSString).length)
    #expect(textView.vimEngine?.mode == .insert)
  }

  @Test("cB keeps indentation and leaves the cursor after the bullet marker")
  func cShiftBKeepsIndentedBulletMarker() {
    let text = "  - Nested task"
    let textView = makeVimMotionTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.setSelectedRange(NSRange(location: ("  - Nested" as NSString).length, length: 0))

    textView.keyDown(with: keyEvent(characters: "c", ignoring: "c", keyCode: 8))
    textView.keyDown(with: keyEvent(characters: "B", ignoring: "b", keyCode: 11, modifiers: .shift))

    #expect(textView.string == "  - ")
    #expect(textView.selectedRange.location == ("  - " as NSString).length)
    #expect(textView.vimEngine?.mode == .insert)
  }
}
