import AppKit
import Testing

@testable import Spotlight

// Hint labels draw as bare colored letters in the anchor's character cell
// (`drawHintLabel`, nvim's foreground-only `hl_mode = "replace"` look).
// The covered glyphs hide via a `.clear` TEMPORARY foreground -- layout
// keeps every advance -- while the note STRING itself is never edited
// (character replacement garbled the proportional-font note, David
// 2026-08-09; the opaque pink pill chips were retired 2026-08-10). The
// hidden span is advance-MEASURED (`hintHiddenRange`): the editor font
// is proportional, so a fixed label-length hide let wide labels collide
// with the next glyph (David 2026-08-10, "flash hints all messed up").
@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  @Test("the hidden span is advance-measured: labels cover their cells on the mono grid, never past a newline")
  func hintHiddenRangeMeasuresLabelInk() {
    let textView = makeVimMotionTextView(text: "i\nii William")

    let clipped = textView.hintHiddenRange(at: 0, label: "gs", bold: false)
    #expect(clipped == NSRange(location: 0, length: 1), "the span never crosses a line break")

    let two = textView.hintHiddenRange(at: 2, label: "gs", bold: false)
    #expect(two == NSRange(location: 2, length: 2), "a two-char label covers two mono cells")

    let one = textView.hintHiddenRange(at: 5, label: "i", bold: false)
    #expect(one == NSRange(location: 5, length: 1), "a one-char label hides only its anchor")
  }

  @Test("bold trait conversion stays in the mono family and keeps the advance (labels stay on-grid)")
  func boldFlashLabelsKeepTheMonoAdvance() {
    let editor = SpotNoteFont.editor()
    let bold = NSFontManager.shared.convert(editor, toHaveTrait: .boldFontMask)
    #expect(bold.fontName == "LilexNFM-Bold", "flash labels need the family's true bold")
    let advance = ("W" as NSString).size(withAttributes: [.font: editor]).width
    let boldAdvance = ("W" as NSString).size(withAttributes: [.font: bold]).width
    #expect(abs(advance - boldAdvance) < 0.01, "bold keeps the mono advance so labels stay on-grid")
  }

  @Test("word-hint anchors hide under their labels; the rest only dims and the text never mutates")
  func wordHintLabelsHideAnchorsWithoutMutatingText() {
    let textView = makeVimMotionTextView(text: "alpha beta gamma")
    let controller = VimController()
    textView.attachVimController(controller)
    textView.vimModeEnabled = true
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "s", ignoring: "s", keyCode: 1))

    #expect(controller.prompt?.kind == .wordHint)
    for location in [0, 6, 11] {
      #expect((temporaryForegroundColor(at: location, in: textView)?.alphaComponent ?? 1) < 0.01)
    }
    let dimmed = temporaryForegroundColor(at: 2, in: textView)?.alphaComponent ?? 0
    #expect(dimmed > 0.3 && dimmed < 0.6, "non-anchor text dims, never blanks")
    #expect(textView.string == "alpha beta gamma")
  }

  @Test("Flash label anchors hide while the query chars stay lit; the text never mutates")
  func flashLabelsHideAnchorsWithoutMutatingText() {
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
    #expect(
      (temporaryForegroundColor(at: labelAnchorLocation, in: textView)?.alphaComponent ?? 1) < 0.01
    )
    #expect(
      (temporaryForegroundColor(at: firstTargetLocation, in: textView)?.alphaComponent ?? 0) > 0.5,
      "the matched query chars stay bright under the label"
    )
    #expect(textView.string == "x not now notion")
  }
}
