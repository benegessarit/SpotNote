import AppKit
import Testing

@testable import Spotlight

@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  @Test("Shift-K keyDown opens visible row Flash labels")
  func shiftKKeyDownOpensLineFlash() {
    let textView = makeVimMotionTextView(text: "one\ntwo\nthree")
    let scrollView = makeScrollView(containing: textView)
    let ruler = LineNumberRuler(
      textView: textView,
      editorFont: textView.font ?? SpotNoteFont.editor(),
      showsLineNumbers: false
    )
    scrollView.verticalRulerView = ruler
    scrollView.hasVerticalRuler = true
    scrollView.rulersVisible = true
    let controller = VimController()
    textView.attachVimController(controller)
    textView.vimModeEnabled = true
    #expect(ruler.ruleThickness == 0)

    textView.keyDown(with: keyEvent(characters: "K", ignoring: "k", keyCode: 40, modifiers: .shift))

    #expect(controller.prompt?.kind == .lineFlash(count: 1))
    #expect(textView.isShowingLineFlashHints)
    #expect(Array(textView.flashHints.map(\.label).prefix(3)) == ["a", "s", "d"])
    #expect(ruler.ruleThickness > 0)

    textView.keyDown(with: keyEvent(characters: "\u{1B}", ignoring: "\u{1B}", keyCode: 53))

    #expect(!textView.isShowingLineFlashHints)
    #expect(ruler.ruleThickness == 0)
  }
}
