import AppKit
import Testing

@testable import Spotlight

// Hint labels draw as opaque chips over the anchor glyph (`drawHintChip`);
// they must never blank/`.clear` the underlying characters. hop's
// `hl_mode = "replace"` glyph-swap garbled the proportional-font note
// (David, 2026-08-09) and is deliberately not ported.
@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  @Test("word-hint labels never blank the note text; chips draw over it")
  func wordHintLabelsKeepWordStartsVisible() {
    let textView = makeVimMotionTextView(text: "alpha beta gamma")
    let controller = VimController()
    textView.attachVimController(controller)
    textView.vimModeEnabled = true
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "s", ignoring: "s", keyCode: 1))

    #expect(controller.prompt?.kind == .wordHint)
    for location in [0, 6, 11] {
      #expect((temporaryForegroundColor(at: location, in: textView)?.alphaComponent ?? 0) > 0.01)
    }
  }

  @Test("Flash labels never blank the note text; chips draw over it")
  func flashLabelsKeepAnchorCharactersVisible() {
    let textView = makeVimMotionTextView(text: "x not now notion")
    let controller = VimController()
    textView.attachVimController(controller)
    textView.vimModeEnabled = true
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "f", ignoring: "f", keyCode: 3))
    textView.keyDown(with: keyEvent(characters: "n", ignoring: "n", keyCode: 45))
    textView.keyDown(with: keyEvent(characters: "o", ignoring: "o", keyCode: 31))

    let firstTargetLocation = ("x " as NSString).length
    let labelAnchorLocation = firstTargetLocation + ("no" as NSString).length
    #expect(textView.flashHints.first?.label == "a")
    #expect((temporaryForegroundColor(at: labelAnchorLocation, in: textView)?.alphaComponent ?? 0) > 0.01)
  }
}
