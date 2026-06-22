// swiftlint:disable file_length
import AppKit
import SwiftUI
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor token replacement")
struct MultilineEditorTokenTests {
  @Test("return after @today normalization updates binding and grows to two rows")
  func returnAfterTodayNormalizationUpdatesHeight() {
    var boundText = ""
    var heights: [CGFloat] = []
    let parent = MultilineEditor(
      text: Binding(
        get: { boundText },
        set: { boundText = $0 }
      ),
      theme: ThemeCatalog.obsidian,
      placeholder: "",
      showLineNumbers: false,
      font: .systemFont(ofSize: EditorMetrics.fontSize),
      focusRequest: 0,
      maxVisibleLines: 4,
      extraChromeHeight: 0,
      onHeightChange: { heights.append($0) }
    )
    let coordinator = MultilineEditor.Coordinator(parent)
    let textView = makeTextView()

    insert("@today", into: textView)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    #expect(boundText.matchesDateLine)

    let date = boundText
    insert("\n", into: textView)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

    #expect(boundText == "\(date)\n")
    #expect(heights.last == EditorMetrics.panelHeight(forLines: 2, maxLines: 4))
  }

  @Test("return after @cl keeps literal text and grows to two rows")
  func returnAfterChecklistLiteralUpdatesHeight() {
    var boundText = ""
    var heights: [CGFloat] = []
    let parent = MultilineEditor(
      text: Binding(
        get: { boundText },
        set: { boundText = $0 }
      ),
      theme: ThemeCatalog.obsidian,
      placeholder: "",
      showLineNumbers: false,
      font: .systemFont(ofSize: EditorMetrics.fontSize),
      focusRequest: 0,
      maxVisibleLines: 4,
      extraChromeHeight: 0,
      onHeightChange: { heights.append($0) }
    )
    let coordinator = MultilineEditor.Coordinator(parent)
    let textView = makeTextView()

    insert("@cl", into: textView)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    #expect(boundText == "@cl")
    #expect(textView.checklistLines.isEmpty)

    insert("\n", into: textView)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

    #expect(boundText == "@cl\n")
    #expect(textView.checklistLines.isEmpty)
    #expect(heights.last == EditorMetrics.panelHeight(forLines: 2, maxLines: 4))
  }

  @Test("@today renders at the token location instead of moving to the first line")
  func todayRendersInPlace() {
    let context = makeEditorContext(initialText: "first line\n")

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    let parts = context.boundText().components(separatedBy: "\n")
    #expect(parts.count == 2)
    #expect(parts.first == "first line")
    #expect(parts.last?.matchesDateLine == true)
  }

  @Test("cmd+z after @today rendering restores literal and suppresses immediate re-render")
  func commandZAfterTodayRenderingRestoresLiteral() throws {
    let context = makeEditorContext()

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    pressCommandZ(in: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "@today")

    insert("!", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "@today!")
  }

  @Test("backspace after @today rendering reverts even if AppKit leaves caret at original token end")
  func backspaceAfterTodayRenderingWithOriginalCaretPositionRestoresLiteral() throws {
    let context = makeEditorContext()

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    context.textView.setSelectedRange(NSRange(location: ("@today" as NSString).length, length: 0))
    pressBackspace(in: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "@today")
  }

  @Test("direct deleteBackward after @today rendering restores literal")
  func directDeleteBackwardAfterTodayRenderingRestoresLiteral() throws {
    let context = makeEditorContext()

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    context.textView.deleteBackward(nil)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "@today")
  }

  @Test("delegate notification during @today revert does not immediately re-render")
  func delegateNotificationDuringTodayRevertDoesNotRerender() throws {
    let context = makeEditorContext(connectDelegate: true)

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    context.textView.deleteBackward(nil)

    #expect(context.boundText() == "@today")
    #expect(context.textView.selectedRange.location == ("@today" as NSString).length)
  }

  @Test("deleting and retyping a restored token renders it again")
  func deletingAndRetypingRestoredTokenRendersAgain() throws {
    let context = makeEditorContext()

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    pressCommandZ(in: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    replace(
      range: NSRange(location: 0, length: (context.boundText() as NSString).length),
      with: "",
      in: context.textView
    )
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText().matchesDateLine)
  }

  private struct EditorContext {
    let coordinator: MultilineEditor.Coordinator
    let textView: PlaceholderTextView
    let boundText: () -> String
  }

  private func makeEditorContext(initialText: String = "", connectDelegate: Bool = false) -> EditorContext {
    var boundText = initialText
    var heights: [CGFloat] = []
    let parent = MultilineEditor(
      text: Binding(
        get: { boundText },
        set: { boundText = $0 }
      ),
      theme: ThemeCatalog.obsidian,
      placeholder: "",
      showLineNumbers: false,
      font: .systemFont(ofSize: EditorMetrics.fontSize),
      focusRequest: 0,
      maxVisibleLines: 4,
      extraChromeHeight: 0,
      onHeightChange: { heights.append($0) }
    )
    let textView = makeTextView()
    textView.string = initialText
    textView.setSelectedRange(NSRange(location: (initialText as NSString).length, length: 0))
    let coordinator = MultilineEditor.Coordinator(parent)
    if connectDelegate {
      textView.delegate = coordinator
    }
    return EditorContext(
      coordinator: coordinator,
      textView: textView,
      boundText: { boundText }
    )
  }

  private func makeTextView() -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 200))
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.minimumLineHeight = EditorMetrics.lineHeight
    paragraphStyle.maximumLineHeight = EditorMetrics.lineHeight
    textView.defaultParagraphStyle = paragraphStyle
    textView.editorTextAttributes = [
      .font: textView.font ?? NSFont.systemFont(ofSize: EditorMetrics.fontSize),
      .paragraphStyle: paragraphStyle
    ]
    textView.typingAttributes = textView.editorTextAttributes
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
    return textView
  }

  private func insert(_ replacement: String, into textView: PlaceholderTextView) {
    let range = textView.selectedRange
    replace(range: range, with: replacement, in: textView)
  }

  private func replace(range: NSRange, with replacement: String, in textView: PlaceholderTextView) {
    _ = textView.shouldChangeText(in: range, replacementString: replacement)
    let nsString = textView.string as NSString
    textView.string = nsString.replacingCharacters(in: range, with: replacement)
    textView.setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
  }

}

@MainActor
private func pressCommandZ(in textView: PlaceholderTextView) {
  guard
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: .command,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "z",
      charactersIgnoringModifiers: "z",
      isARepeat: false,
      keyCode: 6
    )
  else { return }
  textView.keyDown(with: event)
}

@MainActor
private func pressBackspace(in textView: PlaceholderTextView) {
  guard
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "\u{7F}",
      charactersIgnoringModifiers: "\u{7F}",
      isARepeat: false,
      keyCode: 51
    )
  else { return }
  textView.keyDown(with: event)
}

@MainActor
@Suite("Multiline editor checklist toggles")
struct MultilineEditorChecklistToggleTests {
  @Test("copy returns visible text only")
  func copyReturnsVisibleTextOnly() {
    let textView = makeChecklistTextView(text: "one\ntwo", checklistLines: [0: .unchecked, 1: .checked])
    textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))

    textView.copy(nil)

    #expect(NSPasteboard.general.string(forType: .string) == "one\ntwo")
  }

  @Test("deleting a checklist line drops its state and shifts later states")
  func deletingChecklistLineShiftsLaterStates() {
    let textView = makeChecklistTextView(
      text: "one\ntwo\nthree",
      checklistLines: [0: .unchecked, 1: .checked, 2: .unchecked]
    )
    let range = (textView.string as NSString).lineRange(
      for: NSRange(location: ("one\n" as NSString).length, length: 0)
    )

    #expect(textView.shouldChangeText(in: range, replacementString: ""))
    textView.replaceCharacters(in: range, with: "")
    textView.didChangeText()

    #expect(textView.string == "one\nthree")
    #expect(textView.checklistLines == [0: .unchecked, 1: .unchecked])
  }

  @Test("inserting a line before a checklist line keeps the downstream state")
  func insertingLineBeforeChecklistPreservesDownstreamState() {
    let textView = makeChecklistTextView(
      text: "one\ntwo",
      checklistLines: [1: .checked]
    )
    let insertion = ("one\n" as NSString).length

    #expect(textView.shouldChangeText(in: NSRange(location: insertion, length: 0), replacementString: "\n"))
    textView.replaceCharacters(in: NSRange(location: insertion, length: 0), with: "\n")
    textView.didChangeText()

    #expect(textView.string == "one\n\ntwo")
    #expect(textView.checklistLines == [2: .checked])
  }

  @Test("caret erase uses previously painted rect after selection moves")
  func caretEraseUsesPreviousPaintedRectAfterSelectionMoves() {
    let textView = makeChecklistTextView(text: "old caret\nnew caret")
    textView.setSelectedRange(NSRange(location: 3, length: 0))

    let painted = textView.insertionPointDisplayRect(
      for: NSRect(x: 30, y: 0, width: 1, height: EditorMetrics.lineHeight),
      turnedOn: true
    )
    let image = NSImage(size: NSSize(width: 240, height: 80))
    image.lockFocus()
    defer { image.unlockFocus() }
    textView.drawInsertionPoint(in: painted, color: .labelColor, turnedOn: true)
    textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))

    let erase = textView.insertionPointDisplayRect(
      for: NSRect(x: 160, y: EditorMetrics.lineHeight, width: 1, height: EditorMetrics.lineHeight),
      turnedOn: false
    )

    #expect(erase == painted)
  }

  private func makeChecklistTextView(
    text: String,
    checklistLines: [Int: ChecklistLineState] = [:]
  ) -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 200))
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
    return textView
  }

}
