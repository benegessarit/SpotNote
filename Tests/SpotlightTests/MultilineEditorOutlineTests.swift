import AppKit
import SwiftUI
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor Markdown outline editing")
struct MultilineEditorOutlineTests {
  @Test("Markdown bullet prefix continues on insert newline")
  func insertNewlineContinuesBulletPrefix() {
    let textView = makeTextView(text: "- Call Dana")
    textView.setSelectedRange(NSRange(location: ("- Call Dana" as NSString).length, length: 0))

    textView.insertNewline(nil)

    #expect(textView.string == "- Call Dana\n- ")
    #expect(textView.selectedRange.location == ("- Call Dana\n- " as NSString).length)
  }

  @Test("insert newline on a nested bullet keeps its indentation")
  func insertNewlineContinuesNestedBulletPrefix() {
    let textView = makeTextView(text: "  - Nested task")
    textView.setSelectedRange(NSRange(location: ("  - Nested task" as NSString).length, length: 0))

    textView.insertNewline(nil)

    #expect(textView.string == "  - Nested task\n  - ")
  }

  @Test("normal-mode o under a bullet opens a matching bullet below")
  func normalModeOContinuesBulletBelow() {
    let textView = makeNormalModeTextView(text: "- Call Dana\nplain")
    textView.setSelectedRange(NSRange(location: 2, length: 0))

    textView.keyDown(with: keyEvent(characters: "o", ignoring: "o", keyCode: 31))

    #expect(textView.string == "- Call Dana\n- \nplain")
    #expect(textView.selectedRange.location == ("- Call Dana\n- " as NSString).length)
  }

  @Test("normal-mode O above a bullet opens a matching bullet above")
  func normalModeShiftOContinuesBulletAbove() {
    let textView = makeNormalModeTextView(text: "- Call Dana")
    textView.setSelectedRange(NSRange(location: 2, length: 0))

    textView.keyDown(with: keyEvent(characters: "O", ignoring: "O", keyCode: 31, modifiers: .shift))

    #expect(textView.string == "- \n- Call Dana")
    #expect(textView.selectedRange.location == ("- " as NSString).length)
  }

  @Test("normal-mode O at document start opens an editable bullet above the top bullet")
  func normalModeShiftOAtDocumentStartContinuesBulletAbove() {
    let textView = makeNormalModeTextView(text: "- Call Dana")
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.keyDown(with: keyEvent(characters: "O", ignoring: "O", keyCode: 31, modifiers: .shift))

    #expect(textView.string == "- \n- Call Dana")
    #expect(textView.selectedRange.location == ("- " as NSString).length)
  }

  @Test("tab indents the current bullet line by one outline level")
  func tabIndentsBulletLine() {
    let textView = makeTextView(text: "- Call Dana")
    textView.setSelectedRange(NSRange(location: 4, length: 0))

    textView.keyDown(with: keyEvent(characters: "\t", ignoring: "\t", keyCode: 48))

    #expect(textView.string == "  - Call Dana")
    #expect(textView.selectedRange.location == 6)
  }

  @Test("shift-tab outdents the current bullet line by one outline level")
  func shiftTabOutdentsBulletLine() {
    let textView = makeTextView(text: "  - Call Dana")
    textView.setSelectedRange(NSRange(location: 6, length: 0))

    textView.keyDown(
      with: keyEvent(characters: "\u{19}", ignoring: "\t", keyCode: 48, modifiers: .shift)
    )

    #expect(textView.string == "- Call Dana")
    #expect(textView.selectedRange.location == 4)
  }

  @Test("pressing return on an empty bullet cycles to x then a flush-left blank")
  func emptyBulletReturnCyclesToDoneMarkerThenFlushBlank() {
    let textView = makeTextView(text: "- ")
    textView.setSelectedRange(NSRange(location: 2, length: 0))

    textView.insertNewline(nil)

    #expect(textView.string == "x")
    #expect(textView.selectedRange.location == 1)

    textView.insertNewline(nil)

    #expect(textView.string.isEmpty)
    #expect(textView.selectedRange.location == 0)
  }

  @Test("normal-mode return toggles a line into and out of a wrapped bullet")
  func normalModeReturnTogglesLineBullet() throws {
    let textView = makeNormalModeTextView(text: "Call Dana")
    let editor = makeEditor(text: textView.string)
    textView.setSelectedRange(NSRange(location: 4, length: 0))

    textView.keyDown(with: returnKeyEvent())
    editor.ensureParagraphStyle(on: textView)

    #expect(textView.string == "- Call Dana")
    #expect(textView.selectedRange.location == 6)
    let bulletStyle = try #require(paragraphStyle(in: textView, at: 0))
    #expect(abs(bulletStyle.headIndent - prefixWidth("- ", in: textView)) < 0.5)

    textView.keyDown(with: returnKeyEvent())
    editor.ensureParagraphStyle(on: textView)

    #expect(textView.string == "Call Dana")
    #expect(textView.selectedRange.location == 4)
    let plainStyle = try #require(paragraphStyle(in: textView, at: 0))
    #expect(plainStyle.headIndent == 0)
  }

  @Test("normal-mode return cycles a bare dash into x and then a flush-left blank")
  func normalModeReturnCyclesBareDashThroughDoneMarker() throws {
    let textView = makeNormalModeTextView(text: "-")
    let editor = makeEditor(text: textView.string)
    textView.setSelectedRange(NSRange(location: 1, length: 0))

    textView.keyDown(with: returnKeyEvent())
    editor.ensureParagraphStyle(on: textView)

    #expect(textView.string == "x")
    #expect(textView.selectedRange.location == 1)
    let markerStyle = try #require(paragraphStyle(in: textView, at: 0))
    #expect(markerStyle.headIndent == 0)

    textView.keyDown(with: returnKeyEvent())
    editor.ensureParagraphStyle(on: textView)

    #expect(textView.string.isEmpty)
    #expect(textView.selectedRange.location == 0)
  }

  @Test("normal-mode return clears an indented x marker to a flush-left blank")
  func normalModeReturnClearsIndentedDoneMarkerFlushLeft() {
    let textView = makeNormalModeTextView(text: "  x")
    textView.setSelectedRange(NSRange(location: 3, length: 0))

    textView.keyDown(with: returnKeyEvent())

    #expect(textView.string.isEmpty)
    #expect(textView.selectedRange.location == 0)
  }

  @Test("visual-line return toggles selected lines into bullets")
  func visualLineReturnTogglesSelectedLinesIntoBullets() {
    let textView = makeNormalModeTextView(text: "alpha\nbeta\ngamma")
    textView.setSelectedRange(NSRange(location: 1, length: 0))

    textView.keyDown(with: keyEvent(characters: "V", ignoring: "V", keyCode: 9, modifiers: .shift))
    textView.keyDown(with: keyEvent(characters: "j", ignoring: "j", keyCode: 38))
    textView.keyDown(with: returnKeyEvent())

    #expect(textView.string == "- alpha\n- beta\ngamma")
    #expect(textView.vimEngine?.mode == .normal)
  }

  @Test("plain lines keep normal tab behavior")
  func plainLineDoesNotOutlineIndent() {
    let textView = makeTextView(text: "plain")
    textView.setSelectedRange(NSRange(location: 2, length: 0))

    textView.keyDown(with: keyEvent(characters: "\t", ignoring: "\t", keyCode: 48))

    #expect(textView.string != "  plain")
  }

  @Test("wrapped bullet text hangs under the first body character")
  func bulletParagraphUsesHangingWrapIndent() throws {
    let textView = makeTextView(
      text: "- A long body that should wrap under the A, not under the marker"
    )
    let editor = makeEditor(text: textView.string)

    editor.ensureParagraphStyle(on: textView)

    let style = try #require(paragraphStyle(in: textView, at: 0))
    let expectedIndent = prefixWidth("- ", in: textView)
    #expect(style.firstLineHeadIndent == 0)
    #expect(abs(style.headIndent - expectedIndent) < 0.5)
  }

  @Test("plain paragraphs keep full-width wrapping")
  func plainParagraphKeepsZeroWrapIndent() throws {
    let textView = makeTextView(text: "plain note")
    let editor = makeEditor(text: textView.string)

    editor.ensureParagraphStyle(on: textView)

    let style = try #require(paragraphStyle(in: textView, at: 0))
    #expect(style.firstLineHeadIndent == 0)
    #expect(style.headIndent == 0)
  }

  @Test("nested wrapped bullet text hangs under its nested body")
  func nestedBulletParagraphUsesNestedHangingWrapIndent() throws {
    let textView = makeTextView(text: "  - Nested body that should wrap under the N")
    let editor = makeEditor(text: textView.string)

    editor.ensureParagraphStyle(on: textView)

    let style = try #require(paragraphStyle(in: textView, at: 0))
    let expectedIndent = prefixWidth("  - ", in: textView)
    #expect(style.firstLineHeadIndent == 0)
    #expect(abs(style.headIndent - expectedIndent) < 0.5)
  }

  private func makeTextView(text: String) -> PlaceholderTextView {
    let textView = PlaceholderTextView(
      frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 200)
    )
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    return textView
  }

  private func makeEditor(text: String) -> MultilineEditor {
    MultilineEditor(
      text: Binding.constant(text),
      theme: ThemeCatalog.obsidian,
      placeholder: "",
      showLineNumbers: false,
      font: .systemFont(ofSize: EditorMetrics.fontSize),
      focusRequest: 0,
      maxVisibleLines: 4,
      extraChromeHeight: 0,
      onHeightChange: { _ in }
    )
  }

  private func paragraphStyle(
    in textView: PlaceholderTextView,
    at location: Int
  ) -> NSParagraphStyle? {
    textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil)
      as? NSParagraphStyle
  }

  private func prefixWidth(_ prefix: String, in textView: PlaceholderTextView) -> CGFloat {
    let font = textView.font ?? .systemFont(ofSize: EditorMetrics.fontSize)
    return ceil((prefix as NSString).size(withAttributes: [.font: font]).width)
  }

  private func makeNormalModeTextView(text: String) -> PlaceholderTextView {
    let textView = makeTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    return textView
  }

  private func returnKeyEvent() -> NSEvent {
    keyEvent(characters: "\r", ignoring: "\r", keyCode: 36)
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
