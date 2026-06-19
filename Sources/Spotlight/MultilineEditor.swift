// swiftlint:disable file_length type_body_length function_body_length function_parameter_count
import AppKit
import SwiftUI

/// The HUD's text surface -- `NSTextView` in an `NSScrollView` with a
/// custom `NSRulerView` line-number gutter.
///
/// Baselines are computed using `NSLayoutManager.location(forGlyphAt:)`
/// rather than ascender-only heuristics, so the number's glyph baseline
/// lands on the exact same y as the text's glyph baseline even when the
/// paragraph line height differs from the font's natural line height.
/// A separate text-container inset puts a deliberate gap between the
/// gutter and where the caret sits.
struct MultilineEditor: NSViewRepresentable {
  @Binding var text: String
  var checklistLines: [Int: ChecklistLineState] = [:]
  var onChecklistLinesChange: ([Int: ChecklistLineState]) -> Void = { _ in }
  let theme: Theme
  let placeholder: String
  let showLineNumbers: Bool
  let font: NSFont
  let focusRequest: Int
  /// Counter from `FocusTrigger.caretEndTick`; when it changes, the
  /// editor moves the caret to the very end of `text`. Used by the
  /// append-to-last-note global hotkey.
  var caretEndRequest: Int = 0
  /// Upper bound (in display rows) that the panel grows to before
  /// scrolling. Surfaced from user preferences so the setting can be
  /// tuned between 1 and `ThemePreferences.maxVisibleLinesCap` at
  /// runtime.
  let maxVisibleLines: Int
  /// Extra vertical space owned by chrome outside the editor card
  /// (currently: the optional tutorial bar). Added on top of the
  /// editor's own computed height so the panel can host both without
  /// the editor having to know what's above it.
  let extraChromeHeight: CGFloat
  /// Range to select and scroll into view -- driven by the find bar's
  /// current match. `nil` leaves the user's selection / cursor alone.
  var findHighlight: NSRange?
  var vimModeEnabled: Bool = false
  /// Owning controller used to mirror normal/insert mode into SwiftUI
  /// state, drive the `:` / `/` prompt buffer, and dispatch parsed
  /// commands. `nil` while vim mode is off (the editor short-circuits
  /// every vim-related branch in that case).
  var vimController: VimController?
  /// Invoked when Esc should dismiss the HUD. Fires only when vim mode
  /// is off, or when vim mode is on and the engine is already in normal
  /// mode (insert-mode Esc still falls through to the engine to switch
  /// modes first, matching real vim).
  var onEscape: (() -> Void)?
  /// Sends a normalized current-line title to the local Hermes/Marginal
  /// ingress, which creates the Linear issue without embedding Linear
  /// credentials in SpotNote.
  var onSendLinearTask: ((LinearTaskHandoffRequest) async throws -> Void)?
  /// Appends current/counted lines to today's vault daily note. The editor
  /// clears the original lines only after this durable write succeeds.
  var onAppendDailyNote: ((String) async throws -> URL)?
  /// Appends current/counted lines to the completed-items capture file, then
  /// clears the original lines only after this durable write succeeds.
  var onAppendCompletedItems: ((String) async throws -> URL)?
  /// Appends current/counted lines to the misc thoughts dump (`tray.md`), then
  /// clears the original lines only after this durable write succeeds.
  var onAppendTrayNote: ((String) async throws -> URL)?
  /// Called from the AppKit delegate synchronously, so the panel resizes in
  /// the same runloop tick as the text change. A SwiftUI `@State` round-trip
  /// would defer the resize by one runloop, causing a visible flash.
  let onHeightChange: (CGFloat) -> Void

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = makeScrollView()
    let textView = makeTextView(coordinator: context.coordinator)
    replaceLayoutManager(on: textView)
    scroll.documentView = textView
    applyStyle(textView: textView)
    textView.string = text
    textView.checklistLines = checklistLines
    textView.onChecklistLinesChange = onChecklistLinesChange
    textView.placeholderString = placeholder
    refreshAttributes(on: textView)
    configureRuler(scroll: scroll, textView: textView, visible: showLineNumbers)
    installSuggestionField(on: textView)
    textView.vimModeEnabled = vimModeEnabled
    textView.attachVimController(vimController)
    textView.onEscape = onEscape
    textView.onSendLinearTask = onSendLinearTask
    textView.onAppendDailyNote = onAppendDailyNote
    textView.onAppendCompletedItems = onAppendCompletedItems
    textView.onAppendTrayNote = onAppendTrayNote
    return scroll
  }

  private func makeScrollView() -> NSScrollView {
    let scroll = SpotNoteScrollView()
    SpotNoteScrollViewStyle.apply(to: scroll)
    return scroll
  }

  private func makeTextView(coordinator: Coordinator) -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: .zero)
    textView.delegate = coordinator
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.isRichText = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.textContainerInset = NSSize(width: EditorMetrics.textLeadingGap, height: 0)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.autoresizingMask = [.width]
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.smartInsertDeleteEnabled = false
    return textView
  }

  private func installSuggestionField(on textView: PlaceholderTextView) {
    let view = SuggestionView()
    view.isHidden = true
    view.font = font
    view.textColor = NSColor(theme.placeholder).withAlphaComponent(0.75)
    textView.addSubview(view)
    textView.suggestionField = view
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let textView = scroll.documentView as? PlaceholderTextView else { return }
    context.coordinator.parent = self
    if textView.string != text {
      textView.string = text
      refreshAttributes(on: textView)
      textView.vimController?.clearSearchStatus()
    }
    if textView.vimModeEnabled != vimModeEnabled {
      textView.vimModeEnabled = vimModeEnabled
    }
    textView.attachVimController(vimController)
    textView.onEscape = onEscape
    textView.onSendLinearTask = onSendLinearTask
    textView.onAppendDailyNote = onAppendDailyNote
    textView.onAppendCompletedItems = onAppendCompletedItems
    textView.onAppendTrayNote = onAppendTrayNote
    textView.onChecklistLinesChange = onChecklistLinesChange
    applyStyleAndRefreshAttributesIfNeeded(on: textView)
    if textView.checklistLines != checklistLines {
      textView.checklistLines = checklistLines
      textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }
    if textView.placeholderString != placeholder {
      textView.placeholderString = placeholder
      textView.needsDisplay = true
    }
    configureRuler(scroll: scroll, textView: textView, visible: showLineNumbers)

    if context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      DispatchQueue.main.async { [weak textView] in
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
      }
    }
    if context.coordinator.lastCaretEndRequest != caretEndRequest {
      context.coordinator.lastCaretEndRequest = caretEndRequest
      let length = (textView.string as NSString).length
      textView.setSelectedRange(NSRange(location: length, length: 0))
      textView.scrollRangeToVisible(NSRange(location: length, length: 0))
    }

    // Reflect the find bar's current match by selecting + scrolling to
    // it. We only act on a transition so a stable highlight doesn't
    // continually steal the user's caret.
    applyFindHighlight(textView: textView, coordinator: context.coordinator)

    // Re-evaluate the panel height: text (via bindings), `maxVisibleLines`,
    // and `extraChromeHeight` can all change here, and the editor delegate
    // only fires on user-driven text edits.
    context.coordinator.reportHeightIfNeeded(for: textView)

    refreshSuggestion(on: textView)
  }

  /// Recomputes the inline math suggestion and repositions the ghost
  /// field next to the cursor. No-ops when the cursor isn't at an
  /// end-of-line position -- the suggestion would otherwise overlap
  /// existing text.
  func refreshSuggestion(on textView: PlaceholderTextView) {
    guard let field = textView.suggestionField else { return }
    let selection = textView.selectedRange
    guard selection.length == 0 else {
      hideSuggestion(field: field, textView: textView)
      return
    }
    let nsString = textView.string as NSString
    let cursor = selection.location
    let nextChar: unichar? = cursor < nsString.length ? nsString.character(at: cursor) : nil
    let atEndOfLine = nextChar == nil || nextChar == 0x0A  // \n
    guard atEndOfLine else {
      hideSuggestion(field: field, textView: textView)
      return
    }
    guard
      let suggestion = MathSuggester.suggestion(
        text: textView.string,
        cursorOffset: cursor
      )
    else {
      hideSuggestion(field: field, textView: textView)
      return
    }
    showSuggestion(suggestion.answer, at: cursor, field: field, textView: textView)
  }

  private func hideSuggestion(field: SuggestionView, textView: PlaceholderTextView) {
    field.isHidden = true
    textView.pendingSuggestion = nil
  }

  private func showSuggestion(
    _ answer: String,
    at cursor: Int,
    field: SuggestionView,
    textView: PlaceholderTextView
  ) {
    let display = " = \(answer)"
    field.text = display
    field.font = font
    field.textColor = NSColor(theme.placeholder).withAlphaComponent(0.75)
    guard let caret = caretFrame(in: textView, cursor: cursor) else {
      hideSuggestion(field: field, textView: textView)
      return
    }
    let textWidth = field.intrinsicTextWidth()
    field.frame = NSRect(
      x: caret.maxX,
      y: caret.origin.y,
      width: textWidth,
      height: caret.height
    )
    field.isHidden = false
    textView.pendingSuggestion = answer
  }

  /// Returns the textView-local rect of the caret at `cursor`. Uses
  /// `NSLayoutManager` directly rather than `firstRect(forCharacterRange:)`,
  /// which returns `.zero` for zero-length ranges at end-of-text and was
  /// the reason the inline math suggestion never appeared while typing.
  private func caretFrame(in textView: NSTextView, cursor: Int) -> NSRect? {
    guard
      let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer
    else { return nil }
    layoutManager.ensureLayout(for: textContainer)
    let origin = textView.textContainerOrigin
    let nsString = textView.string as NSString
    let length = nsString.length
    if length == 0 {
      return NSRect(
        x: origin.x,
        y: origin.y,
        width: 0,
        height: EditorMetrics.lineHeight
      )
    }
    if cursor <= 0 {
      let frag = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
      return NSRect(
        x: origin.x + frag.minX,
        y: origin.y + frag.minY,
        width: 0,
        height: frag.height
      )
    }
    let priorChar = cursor - 1
    if nsString.character(at: priorChar) == 0x0A {
      let lastGlyph = max(0, layoutManager.numberOfGlyphs - 1)
      let frag = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
      return NSRect(
        x: origin.x + frag.minX,
        y: origin.y + frag.maxY,
        width: 0,
        height: frag.height
      )
    }
    let priorGlyph = layoutManager.glyphIndexForCharacter(at: priorChar)
    let frag = layoutManager.lineFragmentRect(forGlyphAt: priorGlyph, effectiveRange: nil)
    let priorRect = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: priorGlyph, length: 1),
      in: textContainer
    )
    return NSRect(
      x: origin.x + priorRect.maxX,
      y: origin.y + frag.minY,
      width: 0,
      height: frag.height
    )
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MultilineEditor
    var lastFocusRequest: Int = -1
    var lastCaretEndRequest: Int = 0
    var lastFindHighlight: NSRange?
    var normalizedTextAwaitingNotification: String?
    private var lastReportedHeight: CGFloat?

    init(_ parent: MultilineEditor) { self.parent = parent }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? PlaceholderTextView else { return }
      parent.refreshSuggestion(on: textView)
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? PlaceholderTextView else { return }
      if let normalized = normalizedTextAwaitingNotification {
        normalizedTextAwaitingNotification = nil
        if textView.string == normalized {
          return
        }
      }
      if textView.normalizeSpecialTokens() {
        normalizedTextAwaitingNotification = textView.string
      }
      // Resize first -- synchronous and ahead of the SwiftUI @Binding
      // update that happens on the next runloop. Without this ordering,
      // NSTextView had the new line laid out before the panel had grown,
      // which produced the flash when adding lines 2 or 3.
      //
      // Row count = layout fragments, not `\n`-separated logical lines:
      // soft-wrapping should grow the panel the same way pressing Return
      // does, capped at `maxVisibleLines`.
      let rows = LineNumberRuler.displayRowCount(in: textView)
      let editorHeight = EditorMetrics.panelHeight(
        forLines: rows,
        maxLines: parent.maxVisibleLines
      )
      reportHeightIfNeeded(editorHeight + parent.extraChromeHeight)
      parent.ensureParagraphStyle(on: textView)
      parent.text = textView.string
      textView.synchronizeChecklistLinesWithCurrentText()
      parent.onChecklistLinesChange(textView.checklistLines)
      // Stop showing "2/5" once the user starts editing -- match indices
      // are about to be wrong anyway.
      textView.vimController?.clearSearchStatus()
      if let ruler = textView.enclosingScrollView?.verticalRulerView as? LineNumberRuler {
        ruler.updateRequiredThickness()
        ruler.needsDisplay = true
      }
      parent.applyCodeStyling(on: textView)
      parent.refreshSuggestion(on: textView)
      textView.needsDisplay = true
    }

    @MainActor
    func reportHeightIfNeeded(for textView: NSTextView) {
      let rows = LineNumberRuler.displayRowCount(in: textView)
      let editorHeight = EditorMetrics.panelHeight(
        forLines: rows,
        maxLines: parent.maxVisibleLines
      )
      reportHeightIfNeeded(editorHeight + parent.extraChromeHeight)
    }

    @MainActor
    private func reportHeightIfNeeded(_ height: CGFloat) {
      guard lastReportedHeight != height else { return }
      lastReportedHeight = height
      parent.onHeightChange(height)
    }
  }

  private func applyFindHighlight(textView: NSTextView, coordinator: Coordinator) {
    guard let range = findHighlight else {
      coordinator.lastFindHighlight = nil
      return
    }
    let length = (textView.string as NSString).length
    let valid =
      range.location != NSNotFound
      && range.location + range.length <= length
      && coordinator.lastFindHighlight != range
    guard valid else { return }
    coordinator.lastFindHighlight = range
    textView.setSelectedRange(range)
    textView.scrollRangeToVisible(range)
  }

  private var fixedParagraphStyle: NSParagraphStyle {
    MultilineEditor.sharedFixedParagraphStyle
  }

  private static let sharedFixedParagraphStyle: NSParagraphStyle = fixedParagraphStyle(
    headIndent: 0
  )

  private static func fixedParagraphStyle(headIndent: CGFloat) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = EditorMetrics.lineHeight
    style.maximumLineHeight = EditorMetrics.lineHeight
    style.firstLineHeadIndent = 0
    style.headIndent = headIndent
    return style.copy() as? NSParagraphStyle ?? style
  }

  private var textAttributes: [NSAttributedString.Key: Any] {
    [
      .font: font,
      .foregroundColor: NSColor(theme.text),
      .paragraphStyle: fixedParagraphStyle
    ]
  }

  func applyStyleAndRefreshAttributesIfNeeded(on textView: PlaceholderTextView) {
    let needsAttributeRefresh = textViewNeedsAttributeRefresh(textView)
    applyStyle(textView: textView)
    if needsAttributeRefresh {
      refreshAttributes(on: textView)
    }
  }

  func applyStyle(textView: PlaceholderTextView) {
    let newTextColor = NSColor(theme.text)
    let newPlaceholderColor = NSColor(theme.placeholder)
    // `textView.font` / `textView.textColor` are not just passive defaults:
    // on a non-empty NSTextView they rewrite storage attributes. When the
    // caret is in a styled Markdown heading, using them as style-refresh
    // guards erases every heading back to body font/color. Existing text is
    // styled via `refreshAttributes`/`CodeStyler`; these setters are only
    // safe as empty-editor defaults.
    if textView.string.isEmpty, textView.font != font {
      textView.font = font
    }
    if textView.string.isEmpty, textView.textColor != newTextColor {
      textView.textColor = newTextColor
    }
    textView.insertionPointColor = PlaceholderTextView.normalModeCursorColor
    textView.placeholderColor = newPlaceholderColor
    textView.defaultParagraphStyle = fixedParagraphStyle
    textView.typingAttributes = textAttributes
    textView.editorTextAttributes = textAttributes
    if let ruler = textView.enclosingScrollView?.verticalRulerView as? LineNumberRuler {
      ruler.textColor = newPlaceholderColor.withAlphaComponent(0.8)
      ruler.editorFont = font
    }
  }

  private func refreshAttributes(on textView: NSTextView) {
    guard let storage = textView.textStorage else { return }
    let range = NSRange(location: 0, length: storage.length)
    storage.setAttributes(textAttributes, range: range)
    ensureParagraphStyle(on: textView)
    applyCodeStyling(on: textView)
  }

  private func textViewNeedsAttributeRefresh(_ textView: PlaceholderTextView) -> Bool {
    guard
      let currentFont = textView.editorTextAttributes[.font] as? NSFont,
      let nextFont = textAttributes[.font] as? NSFont,
      currentFont == nextFont,
      colorsMatch(
        textView.editorTextAttributes[.foregroundColor] as? NSColor,
        NSColor(theme.text)
      ),
      paragraphStylesMatch(
        textView.editorTextAttributes[.paragraphStyle] as? NSParagraphStyle,
        fixedParagraphStyle
      )
    else { return true }
    return false
  }

  private func colorsMatch(_ lhs: NSColor?, _ rhs: NSColor) -> Bool {
    guard let left = lhs?.usingColorSpace(.sRGB), let right = rhs.usingColorSpace(.sRGB) else {
      return lhs?.isEqual(rhs) == true
    }
    return abs(left.redComponent - right.redComponent) < 0.001
      && abs(left.greenComponent - right.greenComponent) < 0.001
      && abs(left.blueComponent - right.blueComponent) < 0.001
      && abs(left.alphaComponent - right.alphaComponent) < 0.001
  }

  private func paragraphStylesMatch(_ lhs: NSParagraphStyle?, _ rhs: NSParagraphStyle) -> Bool {
    guard let lhs else { return false }
    return lhs.minimumLineHeight == rhs.minimumLineHeight
      && lhs.maximumLineHeight == rhs.maximumLineHeight
      && lhs.firstLineHeadIndent == rhs.firstLineHeadIndent
      && lhs.headIndent == rhs.headIndent
  }

  private func replaceLayoutManager(on textView: NSTextView) {
    guard let storage = textView.textStorage,
      let container = textView.textContainer
    else { return }
    let fixed = FixedLineHeightLayoutManager()
    fixed.fixedLineHeight = EditorMetrics.lineHeight
    fixed.editorFont = font
    if let existing = storage.layoutManagers.first {
      storage.removeLayoutManager(existing)
    }
    storage.addLayoutManager(fixed)
    fixed.addTextContainer(container)
  }

  func ensureParagraphStyle(on textView: NSTextView) {
    guard let storage = textView.textStorage else { return }
    let length = storage.length
    guard length > 0 else { return }
    let text = storage.string as NSString
    storage.beginEditing()
    var location = 0
    while location < length {
      let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
      let contentEnd = lineContentEnd(lineRange, in: text)
      let contentRange = NSRange(
        location: lineRange.location,
        length: max(0, contentEnd - lineRange.location)
      )
      let lineText = contentRange.length > 0 ? text.substring(with: contentRange) : ""
      let desiredStyle = paragraphStyle(forLineText: lineText)
      if shouldApplyParagraphStyle(desiredStyle, to: lineRange, in: storage) {
        storage.addAttribute(.paragraphStyle, value: desiredStyle, range: lineRange)
      }
      let nextLocation = lineRange.location + lineRange.length
      guard nextLocation > location else { break }
      location = nextLocation
    }
    storage.endEditing()
  }

  private func paragraphStyle(forLineText lineText: String) -> NSParagraphStyle {
    guard let prefix = MarkdownOutline.continuationPrefix(in: lineText) else {
      return fixedParagraphStyle
    }
    let indent = ceil((prefix as NSString).size(withAttributes: [.font: font]).width)
    return Self.fixedParagraphStyle(headIndent: indent)
  }

  private func shouldApplyParagraphStyle(
    _ desiredStyle: NSParagraphStyle,
    to range: NSRange,
    in storage: NSTextStorage
  ) -> Bool {
    guard range.length > 0 else { return false }
    let current =
      storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
      as? NSParagraphStyle
    guard let current else { return true }
    return current.minimumLineHeight != desiredStyle.minimumLineHeight
      || current.maximumLineHeight != desiredStyle.maximumLineHeight
      || current.firstLineHeadIndent != desiredStyle.firstLineHeadIndent
      || current.headIndent != desiredStyle.headIndent
  }

  private func lineContentEnd(_ line: NSRange, in text: NSString) -> Int {
    var end = line.location + line.length
    while end > line.location {
      let ch = text.character(at: end - 1)
      guard ch == 0x0A || ch == 0x0D else { break }
      end -= 1
    }
    return end
  }

  func applyCodeStyling(on textView: NSTextView) {
    CodeStyler.apply(to: textView, theme: theme)
  }

  private func configureRuler(scroll: NSScrollView, textView: NSTextView, visible: Bool) {
    let ruler: LineNumberRuler
    if let existing = scroll.verticalRulerView as? LineNumberRuler {
      ruler = existing
    } else {
      ruler = LineNumberRuler(textView: textView, editorFont: font, showsLineNumbers: visible)
      scroll.verticalRulerView = ruler
    }
    if ruler.showsLineNumbers != visible {
      ruler.showsLineNumbers = visible
    }
    scroll.hasVerticalRuler = true
    scroll.rulersVisible = true
  }

}

// MARK: - PlaceholderTextView

final class PlaceholderTextView: NSTextView {
  private enum RenderedTokenKind {
    case today
  }

  private struct RenderedToken {
    let kind: RenderedTokenKind
    let tokenLiteral: String
    let reversionText: String
    let renderedText: String
    let renderedRange: NSRange
  }
  private struct EditContext {
    let range: NSRange
    let replacement: String?
    let isPaste: Bool
  }
  private struct SuppressedTokenOccurrence {
    let literal: String
    let range: NSRange
  }

  var placeholderString: String = ""
  var placeholderColor: NSColor = .secondaryLabelColor
  weak var suggestionField: SuggestionView?
  var pendingSuggestion: String?
  var editorTextAttributes: [NSAttributedString.Key: Any] = [:]
  static let normalModeCursorColor = NSColor(
    srgbRed: 221 / 255,
    green: 179 / 255,
    blue: 255 / 255,
    alpha: 1
  )

  /// Caret position captured when entering visual line mode. The
  /// rendered selection always spans full lines from this anchor to
  /// wherever the caret currently sits, so motions just move the
  /// "tail" of the selection.
  var visualAnchor: Int?
  var visualCaret: Int?
  var visualLineAnchor: Int?
  /// Live caret tracked separately from the selection -- `extendVisualLine`
  /// uses it as the moving end (above OR below the anchor) so motions
  /// extend symmetrically instead of always re-collapsing to a fixed
  /// edge of the snapped line range.
  var visualLineCaret: Int?
  var vimPasteboard: NSPasteboard = .general
  var vimEngine: VimEngine?
  weak var vimController: VimController?
  var onEscape: (() -> Void)?
  var onSendLinearTask: ((LinearTaskHandoffRequest) async throws -> Void)?
  var onAppendDailyNote: ((String) async throws -> URL)?
  var onAppendCompletedItems: ((String) async throws -> URL)?
  var onAppendTrayNote: ((String) async throws -> URL)?
  var checklistLines: [Int: ChecklistLineState] = [:]
  var onChecklistLinesChange: (([Int: ChecklistLineState]) -> Void)?
  var linearTaskToday: Date?
  var flashHints: [VimFlashTarget] = []
  var flashLabelBuffer: String = ""
  var isShowingLineFlashHints = false
  var flashTemporaryAttributeRanges: [NSRange] = []
  private var lastRenderedToken: RenderedToken?
  private var lastEditContext: EditContext?
  private var lastInsertionPointDisplayRect: NSRect?
  var isPasting = false
  private var suppressedOccurrences: [SuppressedTokenOccurrence] = []

  var vimModeEnabled: Bool = false {
    didSet {
      if vimModeEnabled {
        if vimEngine == nil { vimEngine = VimEngine() }
      } else {
        vimEngine = nil
        clearFlashHints()
      }
      notifyVimModeChanged()
      needsDisplay = true
    }
  }

  override func keyDown(with event: NSEvent) {
    stabilizeTypingAttributes()
    let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
    let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if mods == .command, chars == "z", revertLastRenderedTokenIfPossible() {
      return
    }
    if mods.isEmpty, event.keyCode == 51, revertLastRenderedTokenIfPossible() {
      return
    }
    if let controller = vimController, controller.prompt != nil {
      if handlePromptKey(event: event, controller: controller, mods: mods) { return }
    }
    if mods == .control, chars == "w" {
      deleteWordBackward(self)
      return
    }
    if mods == .control, chars == "u" {
      deleteToBeginningOfLine(self)
      return
    }
    if let engine = vimEngine {
      if !handleVimKey(event: event, engine: engine, mods: mods, chars: chars) {
        super.keyDown(with: event)
      }
      return
    }
    if event.keyCode == 53 {
      onEscape?()
      return
    }
    if handleCompletionOrMarkdownOutlineTab(event: event, modifiers: mods) {
      return
    }
    super.keyDown(with: event)
  }

  private func handleCompletionOrMarkdownOutlineTab(
    event: NSEvent,
    modifiers mods: NSEvent.ModifierFlags
  ) -> Bool {
    if mods.isEmpty, let suggestion = pendingSuggestion, shouldAcceptSuggestion(event: event) {
      acceptSuggestion(suggestion)
      return true
    }
    return handleMarkdownOutlineTab(event: event, modifiers: mods)
  }

  func handleMarkdownOutlineTab(event: NSEvent, modifiers mods: NSEvent.ModifierFlags) -> Bool {
    guard event.keyCode == 48, mods.subtracting(.shift).isEmpty else { return false }
    return adjustCurrentMarkdownOutlineLine(outdent: mods.contains(.shift))
  }

  override func deleteBackward(_ sender: Any?) {
    if revertLastRenderedTokenIfPossible() { return }
    super.deleteBackward(sender)
  }

  override func insertNewline(_ sender: Any?) {
    if insertMarkdownOutlineNewline() { return }
    super.insertNewline(sender)
  }

  override func insertTab(_ sender: Any?) {
    if adjustCurrentMarkdownOutlineLine(outdent: false) { return }
    super.insertTab(sender)
  }

  override func insertBacktab(_ sender: Any?) {
    if adjustCurrentMarkdownOutlineLine(outdent: true) { return }
    super.insertBacktab(sender)
  }

  override func paste(_ sender: Any?) {
    isPasting = true
    defer { isPasting = false }
    super.paste(sender)
  }

  override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
    stabilizeTypingAttributes()
    lastEditContext = EditContext(
      range: affectedCharRange,
      replacement: replacementString,
      isPaste: isPasting
    )
    let allowed = super.shouldChangeText(
      in: affectedCharRange,
      replacementString: replacementString
    )
    if allowed {
      applyChecklistLineEdit(
        affectedRange: affectedCharRange,
        replacementString: replacementString ?? ""
      )
    }
    return allowed
  }

  func synchronizeChecklistLinesWithCurrentText() {
    setChecklistLines(ChecklistDocument.prunedChecklistLines(checklistLines, for: string))
  }

  private func applyChecklistLineEdit(affectedRange: NSRange, replacementString: String) {
    let before = string as NSString
    guard affectedRange.location <= before.length,
      affectedRange.location + affectedRange.length <= before.length
    else { return }
    let insertedNewlines = newlineCount(in: replacementString)
    guard affectedRange.length > 0 || insertedNewlines > 0 else { return }
    let removed = before.substring(with: affectedRange)
    let removedNewlines = newlineCount(in: removed)
    let delta = insertedNewlines - removedNewlines
    let affectedEnd = affectedRange.location + affectedRange.length
    let after = before.replacingCharacters(in: affectedRange, with: replacementString) as NSString
    let lineRanges = logicalLineRanges(in: before)
    var updated: [Int: ChecklistLineState] = [:]
    for (index, state) in checklistLines.sorted(by: { $0.key < $1.key }) {
      guard index >= 0, index < lineRanges.count else { continue }
      let lineRange = lineRanges[index]
      let lineEnd = lineRange.location + lineRange.length
      let target: Int?
      if affectedRange.length == 0 {
        let lineIsVisiblyEmpty = lineContentEnd(lineRange, in: before) == lineRange.location
        let insertsBeforeLine =
          affectedRange.location < lineRange.location
          || (affectedRange.location == lineRange.location && !lineIsVisiblyEmpty)
        target = insertsBeforeLine ? index + insertedNewlines : index
      } else if lineEnd <= affectedRange.location {
        target = index
      } else if lineRange.location >= affectedEnd {
        target = index + delta
      } else if lineRange.location >= affectedRange.location, lineEnd <= affectedEnd {
        target = nil
      } else {
        target = lineIndex(containing: min(lineRange.location, affectedRange.location), in: after)
      }
      if let target, updated[target] == nil {
        updated[target] = state
      }
    }
    setChecklistLines(updated, pruningAgainst: after as String)
  }

  private func setChecklistLines(
    _ updated: [Int: ChecklistLineState],
    pruningAgainst text: String? = nil
  ) {
    let pruned = ChecklistDocument.prunedChecklistLines(updated, for: text ?? string)
    guard pruned != checklistLines else { return }
    checklistLines = pruned
    onChecklistLinesChange?(pruned)
    enclosingScrollView?.verticalRulerView?.needsDisplay = true
  }

  private func logicalLineRanges(in text: NSString) -> [NSRange] {
    if text.length == 0 { return [NSRange(location: 0, length: 0)] }
    var ranges: [NSRange] = []
    var location = 0
    while location < text.length {
      let range = text.lineRange(for: NSRange(location: location, length: 0))
      ranges.append(range)
      location = max(location + 1, range.location + range.length)
    }
    if text.character(at: text.length - 1) == 0x0A {
      ranges.append(NSRange(location: text.length, length: 0))
    }
    return ranges
  }

  private func lineIndex(containing location: Int, in text: NSString) -> Int {
    let clamped = min(max(0, location), text.length)
    guard clamped > 0 else { return 0 }
    let prefix = text.substring(with: NSRange(location: 0, length: clamped))
    return newlineCount(in: prefix)
  }

  private func newlineCount(in text: String) -> Int {
    text.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
  }

  override func tryToPerform(_ action: Selector, with object: Any?) -> Bool {
    if action == Selector(("undo:")), revertLastRenderedTokenIfPossible() {
      return true
    }
    return super.tryToPerform(action, with: object)
  }

  func shouldAcceptSuggestion(event: NSEvent) -> Bool {
    let isTab = event.keyCode == 48
    let isRight = event.keyCode == 124
    guard isTab || isRight else { return false }
    if isTab { return true }
    // Right arrow only accepts when the caret is at the visual end of
    // its line -- anywhere else the user is just navigating.
    let cursor = selectedRange.location
    let nsString = string as NSString
    if cursor >= nsString.length { return true }
    return nsString.character(at: cursor) == 0x0A
  }

  func acceptSuggestion(_ suggestion: String) {
    let insertion = " = \(suggestion)"
    insertText(insertion, replacementRange: NSRange(location: NSNotFound, length: 0))
    pendingSuggestion = nil
    suggestionField?.isHidden = true
  }

  func executeMotion(_ motion: Motion) {
    if let delta = logicalLineDelta(for: motion) {
      moveByLogicalLines(delta)
      return
    }
    if executeVisibleBoundaryMotion(motion) { return }
    if let (selector, count) = repeatedMotion(motion) {
      for _ in 0..<count { selector(self) }
      return
    }
    switch motion {
    case .documentStart:
      moveToDocumentStartForVim()
    case .documentEnd:
      moveToDocumentEndForVim()
    default:
      return
    }
  }

  private func moveToDocumentStartForVim() {
    setSelectedRange(NSRange(location: 0, length: 0))
    if let clipView = enclosingScrollView?.contentView {
      let constrained = clipView.constrainBoundsRect(
        NSRect(origin: .zero, size: clipView.bounds.size)
      )
      clipView.scroll(to: constrained.origin)
      enclosingScrollView?.reflectScrolledClipView(clipView)
    } else {
      scroll(.zero)
    }
    needsDisplay = true
  }

  private func moveToDocumentEndForVim() {
    let length = (string as NSString).length
    setSelectedRange(NSRange(location: length, length: 0))
    if let clipView = enclosingScrollView?.contentView {
      let bottomOriginY = max(
        clipView.documentRect.minY,
        clipView.documentRect.maxY - clipView.bounds.height
      )
      let constrained = clipView.constrainBoundsRect(
        NSRect(
          x: clipView.bounds.origin.x,
          y: bottomOriginY,
          width: clipView.bounds.width,
          height: clipView.bounds.height
        )
      )
      clipView.scroll(to: constrained.origin)
      enclosingScrollView?.reflectScrolledClipView(clipView)
    } else {
      scrollRangeToVisible(NSRange(location: length, length: 0))
    }
    needsDisplay = true
  }

  private func executeVisibleBoundaryMotion(_ motion: Motion) -> Bool {
    switch motion {
    case .left(let count): moveHorizontallyByVisibleColumns(-count)
    case .right(let count): moveHorizontallyByVisibleColumns(count)
    case .lineStart: moveToVisibleLineStart()
    case .lineEnd: moveToEndOfLine(self)
    case .firstNonBlank: moveToFirstNonBlank()
    default: return false
    }
    return true
  }

  private func repeatedMotion(_ motion: Motion) -> ((Any?) -> Void, Int)? {
    switch motion {
    case .wordForward(let count), .wordEnd(let count):
      return (moveWordForward(_:), count)
    case .wordBackward(let count): return (moveWordBackward(_:), count)
    default: return nil
    }
  }

  private func logicalLineDelta(for motion: Motion) -> Int? {
    if case .up(let count) = motion { return -count }
    if case .down(let count) = motion { return count }
    return nil
  }

  private func moveByLogicalLines(_ delta: Int) {
    guard delta != 0 else { return }
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    let cursor = min(selectedRange.location, nsString.length)
    let currentLine = logicalLineRange(containing: cursor, in: nsString)
    let column = visibleColumn(for: cursor, in: currentLine, text: nsString)
    let targetLine = logicalLineRange(moving: delta, from: currentLine, in: nsString)
    setInsertionPoint(rawLocation(forVisibleColumn: column, in: targetLine, text: nsString))
    scrollVimLogicalMotionTargetIntoView()
  }

  private func scrollVimLogicalMotionTargetIntoView() {
    guard let clipView = enclosingScrollView?.contentView else {
      scrollRangeToVisible(selectedRange)
      return
    }
    let caretRect = normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )
    let visible = clipView.documentVisibleRect
    var targetBounds = clipView.bounds
    if caretRect.minY < visible.minY {
      targetBounds.origin.y = caretRect.minY
    } else if caretRect.maxY > visible.maxY {
      targetBounds.origin.y = caretRect.maxY - visible.height
    } else {
      return
    }
    let constrained = clipView.constrainBoundsRect(targetBounds)
    clipView.scroll(to: constrained.origin)
    enclosingScrollView?.reflectScrolledClipView(clipView)
    enclosingScrollView?.flashScrollers()
  }

  private func visibleColumn(for location: Int, in line: NSRange, text nsString: NSString) -> Int {
    let contentEnd = lineContentEnd(line, in: nsString)
    let clampedLocation = min(max(line.location, location), contentEnd)
    return max(0, clampedLocation - line.location)
  }

  private func rawLocation(
    forVisibleColumn column: Int,
    in line: NSRange,
    text nsString: NSString
  ) -> Int {
    let contentEnd = lineContentEnd(line, in: nsString)
    return min(line.location + max(0, column), contentEnd)
  }

  private func moveHorizontallyByVisibleColumns(_ delta: Int) {
    guard delta != 0 else { return }
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    let cursor = min(selectedRange.location, nsString.length)
    let line = logicalLineRange(containing: cursor, in: nsString)
    let contentEnd = lineContentEnd(line, in: nsString)
    let currentColumn = visibleColumn(for: cursor, in: line, text: nsString)
    let finalColumn = visibleColumn(for: contentEnd, in: line, text: nsString)
    let targetColumn = min(max(0, currentColumn + delta), finalColumn)
    setInsertionPoint(rawLocation(forVisibleColumn: targetColumn, in: line, text: nsString))
  }

  private func moveToVisibleLineStart() {
    let nsString = string as NSString
    guard nsString.length > 0 else {
      setInsertionPoint(0)
      return
    }
    let cursor = min(selectedRange.location, nsString.length)
    let line = logicalLineRange(containing: cursor, in: nsString)
    setInsertionPoint(rawLocation(forVisibleColumn: 0, in: line, text: nsString))
  }

  func openLineBelowForVim() {
    openLineForVim(above: false)
  }

  func openLineAboveForVim() {
    openLineForVim(above: true)
  }

  private func openLineForVim(above: Bool) {
    let nsString = string as NSString
    let cursor = min(selectedRange.location, nsString.length)
    let currentLine = logicalLineRange(containing: cursor, in: nsString)
    let currentLineIndex = lineIndex(containing: cursor, in: nsString)
    let originalChecklistLines = checklistLines
    let currentIsChecklist = originalChecklistLines[currentLineIndex] != nil
    let currentLineText = nsString.substring(
      with: NSRange(
        location: currentLine.location,
        length: lineContentEnd(currentLine, in: nsString) - currentLine.location
      )
    )
    let outlinePrefix = MarkdownOutline.continuationPrefix(in: currentLineText)
    let insertionPoint: Int
    let insertionText: String
    let caretAfterInsert: Int
    let newLineIndex: Int
    if above {
      insertionPoint = currentLine.location
      insertionText = outlinePrefix.map { $0 + "\n" } ?? "\n"
      caretAfterInsert = insertionPoint + (outlinePrefix.map { ($0 as NSString).length } ?? 0)
      newLineIndex = currentLineIndex
    } else {
      insertionPoint = currentLine.location + currentLine.length
      let lineHasTerminator =
        currentLine.length > 0
        && insertionPoint <= nsString.length
        && nsString.character(at: insertionPoint - 1) == 0x0A
      if let outlinePrefix {
        insertionText = lineHasTerminator ? outlinePrefix + "\n" : "\n" + outlinePrefix
        caretAfterInsert =
          insertionPoint + (outlinePrefix as NSString).length + (lineHasTerminator ? 0 : 1)
      } else {
        insertionText = "\n"
        caretAfterInsert = lineHasTerminator ? insertionPoint : insertionPoint + 1
      }
      newLineIndex = currentLineIndex + 1
    }

    let range = NSRange(location: insertionPoint, length: 0)
    guard shouldChangeText(in: range, replacementString: insertionText) else { return }
    replaceCharacters(in: range, with: insertionText)
    didChangeText()
    setChecklistLines(
      checklistLinesAfterOpeningVimLine(
        originalChecklistLines,
        newLineIndex: newLineIndex,
        inheritsChecklistState: currentIsChecklist
      )
    )
    let caret = min(caretAfterInsert, (string as NSString).length)
    setInsertionPoint(caret)
    scrollRangeToVisible(NSRange(location: caret, length: 0))
  }

  private func checklistLinesAfterOpeningVimLine(
    _ original: [Int: ChecklistLineState],
    newLineIndex: Int,
    inheritsChecklistState: Bool
  ) -> [Int: ChecklistLineState] {
    var shifted: [Int: ChecklistLineState] = [:]
    for (index, state) in original {
      shifted[index >= newLineIndex ? index + 1 : index] = state
    }
    if inheritsChecklistState {
      shifted[newLineIndex] = .unchecked
    }
    return shifted
  }

  @discardableResult
  private func insertMarkdownOutlineNewline() -> Bool {
    guard selectedRange.length == 0 else { return false }
    let nsString = string as NSString
    let cursor = min(selectedRange.location, nsString.length)
    let line = logicalLineRange(containing: cursor, in: nsString)
    let contentEnd = lineContentEnd(line, in: nsString)
    let lineRange = NSRange(location: line.location, length: contentEnd - line.location)
    let lineText = nsString.substring(with: lineRange)
    guard let prefix = MarkdownOutline.continuationPrefix(in: lineText) else { return false }

    if MarkdownOutline.isBareListItem(lineText) {
      guard shouldChangeText(in: lineRange, replacementString: "") else { return true }
      replaceCharacters(in: lineRange, with: "")
      didChangeText()
      setInsertionPoint(line.location)
      return true
    }

    let insertion = "\n" + prefix
    let range = NSRange(location: cursor, length: 0)
    guard shouldChangeText(in: range, replacementString: insertion) else { return true }
    replaceCharacters(in: range, with: insertion)
    didChangeText()
    setInsertionPoint(cursor + (insertion as NSString).length)
    return true
  }

  @discardableResult
  func adjustCurrentMarkdownOutlineLine(outdent: Bool) -> Bool {
    guard selectedRange.length == 0 else { return false }
    let nsString = string as NSString
    let cursor = min(selectedRange.location, nsString.length)
    let line = logicalLineRange(containing: cursor, in: nsString)
    let contentEnd = lineContentEnd(line, in: nsString)
    let lineRange = NSRange(location: line.location, length: contentEnd - line.location)
    let lineText = nsString.substring(with: lineRange)
    let replacement =
      outdent
      ? MarkdownOutline.outdentedLine(lineText)
      : MarkdownOutline.indentedLine(lineText)
    guard let replacement, replacement != lineText else { return false }
    guard shouldChangeText(in: lineRange, replacementString: replacement) else { return true }
    replaceCharacters(in: lineRange, with: replacement)
    didChangeText()
    let delta = (replacement as NSString).length - lineRange.length
    setInsertionPoint(max(line.location, min(cursor + delta, (string as NSString).length)))
    return true
  }

  private func logicalLineRange(containing cursor: Int, in nsString: NSString) -> NSRange {
    let isTrailingNewline =
      cursor == nsString.length && cursor > 0 && nsString.character(at: cursor - 1) == 0x0A
    if isTrailingNewline {
      return NSRange(location: cursor, length: 0)
    }
    let probe = min(cursor, max(0, nsString.length - 1))
    return nsString.lineRange(for: NSRange(location: probe, length: 0))
  }

  private func logicalLineRange(
    moving delta: Int,
    from line: NSRange,
    in nsString: NSString
  ) -> NSRange {
    var current = line
    if delta > 0 {
      for _ in 0..<delta {
        let nextStart = current.location + current.length
        guard nextStart < nsString.length else {
          let isTrailingNewline =
            nextStart == nsString.length && nsString.length > 0
            && nsString.character(at: nsString.length - 1) == 0x0A
          if isTrailingNewline {
            current = NSRange(location: nextStart, length: 0)
          }
          return current
        }
        current = nsString.lineRange(for: NSRange(location: nextStart, length: 0))
      }
      return current
    }
    for _ in 0..<abs(delta) {
      guard current.location > 0 else { return current }
      current = nsString.lineRange(for: NSRange(location: current.location - 1, length: 0))
    }
    return current
  }

  private func lineContentEnd(_ line: NSRange, in nsString: NSString) -> Int {
    var end = line.location + line.length
    while end > line.location {
      let ch = nsString.character(at: end - 1)
      guard ch == 0x0A || ch == 0x0D else { break }
      end -= 1
    }
    return end
  }

  func executeDeleteMotion(_ motion: Motion) {
    let before = selectedRange.location
    executeMotion(motion)
    let after = selectedRange.location
    let start = min(before, after)
    let length = abs(after - before)
    guard length > 0 else { return }
    setSelectedRange(NSRange(location: start, length: 0))
    insertText("", replacementRange: NSRange(location: start, length: length))
  }

  func executeDeleteLines(_ count: Int) {
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    var range = nsString.lineRange(for: NSRange(location: selectedRange.location, length: 0))
    for _ in 1..<count {
      let nextStart = range.location + range.length
      guard nextStart < nsString.length else { break }
      let nextLine = nsString.lineRange(for: NSRange(location: nextStart, length: 0))
      range.length += nextLine.length
    }
    if range.location > 0, range.location + range.length >= nsString.length {
      range.location -= 1
      range.length += 1
    }
    let cursorAfter = min(range.location, max(0, nsString.length - range.length))
    insertText("", replacementRange: range)
    setSelectedRange(NSRange(location: cursorAfter, length: 0))
  }

  func executeDeleteLinesInsert(_ count: Int) {
    executeDeleteLines(count)
    executeVimAction(.switchToInsert)
  }

  @objc func sendCurrentLineToLinearShortcut(_ sender: Any?) {
    sendCurrentLinesToLinear(1)
  }

  @objc func appendCurrentLineToDailyNoteShortcut(_ sender: Any?) {
    appendCurrentLinesToDailyNote(1)
  }

  @objc func appendCurrentLineToCompletedItemsShortcut(_ sender: Any?) {
    appendCurrentLinesToCompletedItems(1)
  }

  func sendCurrentLinesToLinear(_ count: Int) {
    sendCurrentTaskToLinear(status: .triage, count: count)
  }

  func sendCurrentTaskToLinear(status: LinearTaskTargetStatus, count: Int) {
    guard let onSendLinearTask else {
      vimController?.showMessage("Linear handoff unavailable", kind: .error, icon: .hermes)
      return
    }
    let range = selectedTaskRange(count: max(1, count), in: string as NSString)
    commitSelectedRange(
      range,
      preparing: { [weak self] original, _ in
        LinearTaskMetadataParser.request(
          from: original,
          targetStatus: status,
          today: self?.linearTaskToday ?? Date()
        )
      },
      messages: LineCommitMessages(
        empty: "No Linear task on this bullet",
        progress: "Sending to Linear",
        success: "Sent to Hermes for Linear",
        changed: "Linear sent; bullet changed",
        failure: "Linear send failed"
      ),
      commit: { try await onSendLinearTask($0) }
    )
  }

  func appendCurrentLinesToDailyNote(_ count: Int) {
    guard let onAppendDailyNote else {
      vimController?.showMessage("Daily note handoff unavailable", kind: .error, icon: .hermes)
      return
    }
    commitSelectedLines(
      count: count,
      preparing: { [weak self] original, range in
        self?.dailyNotePayload(for: original, selectedRange: range)
      },
      messages: LineCommitMessages(
        empty: "No daily-note text on this line",
        progress: "Appending to Daily Note",
        success: "Daily note updated",
        changed: "Daily note updated; line changed",
        failure: "Daily note append failed"
      ),
      commit: { _ = try await onAppendDailyNote($0) }
    )
  }

  func appendCurrentLinesToCompletedItems(_ count: Int) {
    guard let onAppendCompletedItems else {
      vimController?.showMessage("Completed-items handoff unavailable", kind: .error, icon: .hermes)
      return
    }
    commitSelectedLines(
      count: count,
      preparing: { [weak self] original, range in
        self?.dailyNotePayload(for: original, selectedRange: range)
      },
      messages: LineCommitMessages(
        empty: "No completed item on this line",
        progress: "Logging completed item",
        success: "Completed item logged",
        changed: "Completed item logged; line changed",
        failure: "Completed item log failed"
      ),
      commit: { _ = try await onAppendCompletedItems($0) }
    )
  }

  func appendCurrentLinesToTrayNote(_ count: Int) {
    guard let onAppendTrayNote else {
      vimController?.showMessage("tray.md handoff unavailable", kind: .error, icon: .hermes)
      return
    }
    commitSelectedLines(
      count: count,
      preparing: { original, _ in TrayNotePayload.normalized(original) },
      messages: LineCommitMessages(
        empty: "No tray.md text on this line",
        progress: "Appending to tray.md",
        success: "Sent to tray.md",
        changed: "Sent to tray.md; line changed",
        failure: "tray.md append failed"
      ),
      commit: { _ = try await onAppendTrayNote($0) }
    )
  }

  private struct LineCommitMessages: Sendable {
    let empty: String
    let progress: String
    let success: String
    let changed: String
    let failure: String
  }

  private func commitSelectedLines<Payload: Sendable>(
    count: Int,
    preparing payloadFor: @escaping (String, NSRange) -> Payload?,
    messages: LineCommitMessages,
    commit: @escaping (Payload) async throws -> Void
  ) {
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    let range = selectedLineRange(count: max(1, count), in: nsString)
    commitSelectedRange(
      range,
      preparing: payloadFor,
      messages: messages,
      commit: commit
    )
  }

  private func commitSelectedRange<Payload: Sendable>(
    _ range: NSRange,
    preparing payloadFor: @escaping (String, NSRange) -> Payload?,
    messages: LineCommitMessages,
    commit: @escaping (Payload) async throws -> Void
  ) {
    let nsString = string as NSString
    guard nsString.length > 0,
      range.location >= 0,
      range.length > 0,
      range.location + range.length <= nsString.length
    else { return }
    let original = nsString.substring(with: range)
    guard let payload = payloadFor(original, range) else {
      vimController?.showMessage(messages.empty, kind: .error, icon: .hermes)
      return
    }
    vimController?.showMessage(messages.progress, kind: .info, icon: .hermes)
    Task { @MainActor [weak self, range, original, payload, messages, commit] in
      guard let self else { return }
      do {
        try await commit(payload)
        let current = self.string as NSString
        guard range.location + range.length <= current.length,
          current.substring(with: range) == original
        else {
          self.vimController?.showMessage(messages.changed, kind: .error, icon: .hermes)
          return
        }
        guard self.shouldChangeText(in: range, replacementString: "") else {
          self.vimController?.showMessage(messages.changed, kind: .error, icon: .hermes)
          return
        }
        self.replaceCharacters(in: range, with: "")
        self.didChangeText()
        let cursor = min(range.location, (self.string as NSString).length)
        self.setSelectedRange(NSRange(location: cursor, length: 0))
        self.vimController?.showMessage(messages.success, kind: .success, icon: .hermes)
      } catch {
        self.vimController?.showMessage(messages.failure, kind: .error, icon: .hermes)
      }
    }
  }

  private func dailyNotePayload(for selectedText: String, selectedRange: NSRange) -> String? {
    let document = string as NSString
    let firstSelectedLine = lineIndex(containing: selectedRange.location, in: document)
    let selectedLineCount = selectedText.components(separatedBy: "\n").count
    var selectedChecklistLines: [Int: ChecklistLineState] = [:]
    for (index, state) in checklistLines {
      let relative = index - firstSelectedLine
      if relative >= 0, relative < selectedLineCount {
        selectedChecklistLines[relative] = state
      }
    }
    let markdown = ChecklistDocument.serializeMarkdown(
      text: selectedText,
      checklistLines: selectedChecklistLines
    )
    return DailyNotePayload.normalized(markdown)
  }

  private struct BulletLineInfo {
    let indent: Int
  }

  private func selectedTaskRange(count: Int, in nsString: NSString) -> NSRange {
    guard nsString.length > 0 else { return NSRange(location: 0, length: 0) }
    let lineRanges = logicalLineRanges(in: nsString)
    let currentLine = min(
      lineIndex(containing: selectedRange.location, in: nsString),
      max(0, lineRanges.count - 1)
    )
    guard
      let firstBullet = bulletStartLine(containing: currentLine, ranges: lineRanges, in: nsString)
    else {
      return selectedLineRange(count: count, in: nsString)
    }

    var finalEnd = bulletBlockEnd(startingAt: firstBullet, ranges: lineRanges, in: nsString)
    var remaining = max(1, count) - 1
    while remaining > 0 {
      guard let nextStart = nextBulletStart(after: finalEnd, ranges: lineRanges, in: nsString)
      else {
        break
      }
      finalEnd = bulletBlockEnd(startingAt: nextStart, ranges: lineRanges, in: nsString)
      remaining -= 1
    }

    let startLocation = lineRanges[firstBullet].location
    let endLine = max(firstBullet, min(finalEnd - 1, lineRanges.count - 1))
    var range = NSRange(
      location: startLocation,
      length: lineRanges[endLine].location + lineRanges[endLine].length - startLocation
    )
    if range.location > 0, range.location + range.length >= nsString.length {
      range.location -= 1
      range.length += 1
    }
    return range
  }

  private func bulletStartLine(
    containing lineIndex: Int,
    ranges: [NSRange],
    in text: NSString
  ) -> Int? {
    var index = min(max(0, lineIndex), max(0, ranges.count - 1))
    while index >= 0 {
      let line = lineText(at: index, ranges: ranges, in: text)
      if bulletInfo(for: line) != nil { return index }
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
      index -= 1
    }
    return nil
  }

  private func bulletBlockEnd(startingAt start: Int, ranges: [NSRange], in text: NSString) -> Int {
    let startIndent = bulletInfo(for: lineText(at: start, ranges: ranges, in: text))?.indent ?? 0
    var index = start + 1
    while index < ranges.count {
      let line = lineText(at: index, ranges: ranges, in: text)
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { break }
      if let info = bulletInfo(for: line), info.indent <= startIndent { break }
      index += 1
    }
    return index
  }

  private func nextBulletStart(after lineIndex: Int, ranges: [NSRange], in text: NSString) -> Int? {
    var index = min(max(0, lineIndex), ranges.count)
    while index < ranges.count {
      if bulletInfo(for: lineText(at: index, ranges: ranges, in: text)) != nil { return index }
      index += 1
    }
    return nil
  }

  private func bulletInfo(for rawLine: String) -> BulletLineInfo? {
    let pattern = #"^([ \t]*)(?:[-*•]|\d+[.)])[ \t]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: rawLine,
        range: NSRange(location: 0, length: (rawLine as NSString).length)
      ),
      let indentRange = Range(match.range(at: 1), in: rawLine)
    else { return nil }
    return BulletLineInfo(indent: rawLine[indentRange].count)
  }

  private func lineText(at index: Int, ranges: [NSRange], in text: NSString) -> String {
    guard index >= 0, index < ranges.count else { return "" }
    let range = ranges[index]
    var length = range.length
    while length > 0 {
      let ch = text.character(at: range.location + length - 1)
      guard ch == 0x0A || ch == 0x0D else { break }
      length -= 1
    }
    return text.substring(with: NSRange(location: range.location, length: length))
  }

  private func selectedLineRange(count: Int, in nsString: NSString) -> NSRange {
    var range = nsString.lineRange(for: NSRange(location: selectedRange.location, length: 0))
    for _ in 1..<count {
      let nextStart = range.location + range.length
      guard nextStart < nsString.length else { break }
      let nextLine = nsString.lineRange(for: NSRange(location: nextStart, length: 0))
      range.length += nextLine.length
    }
    if range.location > 0, range.location + range.length >= nsString.length {
      range.location -= 1
      range.length += 1
    }
    return range
  }

  private func moveToFirstNonBlank() {
    let nsString = string as NSString
    guard nsString.length > 0 else {
      setInsertionPoint(0)
      return
    }
    let cursor = min(selectedRange.location, nsString.length)
    let line = logicalLineRange(containing: cursor, in: nsString)
    let contentEnd = lineContentEnd(line, in: nsString)
    var location = line.location
    while location < contentEnd {
      let ch = nsString.character(at: location)
      guard ch == 0x20 || ch == 0x09 else { break }
      location += 1
    }
    setInsertionPoint(location)
  }

  func notifyVimModeChanged() {
    if let engine = vimEngine {
      vimController?.updateMode(engine.mode)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    drawFlashHints(in: dirtyRect)
    guard string.isEmpty, !placeholderString.isEmpty else { return }
    let effectiveFont = font ?? .systemFont(ofSize: 14)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: effectiveFont,
      .foregroundColor: placeholderColor
    ]
    let baselineInFragment = LineNumberRuler.synthesizedBaseline(
      fragmentHeight: EditorMetrics.lineHeight,
      font: effectiveFont
    )
    let drawY = textContainerOrigin.y + baselineInFragment - effectiveFont.ascender
    let origin = NSPoint(
      x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0),
      y: drawY
    )
    (placeholderString as NSString).draw(at: origin, withAttributes: attrs)
  }

  /// Shrink the blinking caret to the font's ascender-to-descender height
  /// rather than the full 22pt forced-line-height fragment. The fixed
  /// layout manager centers glyphs inside that fragment, so the caret uses
  /// the same vertical inset.
  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    if vimEngine?.mode == .normal {
      let blockRect = normalModeCursorDisplayRect(for: rect, turnedOn: flag)
      if flag {
        lastInsertionPointDisplayRect = blockRect
        Self.normalModeCursorColor.withAlphaComponent(0.82).setFill()
        blockRect.fill()
      } else {
        invalidateInsertionPointRect(blockRect)
      }
    } else {
      let displayRect = insertionPointDisplayRect(for: rect, turnedOn: flag)
      super.drawInsertionPoint(in: displayRect, color: color, turnedOn: flag)
      if flag {
        lastInsertionPointDisplayRect = displayRect
      } else {
        invalidateInsertionPointRect(displayRect)
      }
    }
  }

  func insertionPointDisplayRect(for rect: NSRect, turnedOn flag: Bool) -> NSRect {
    if !flag, let lastInsertionPointDisplayRect {
      return lastInsertionPointDisplayRect
    }
    let baseRect = flag ? normalizedInsertionPointRect(rect) : rect
    return shrinkInsertionPointRectToFont(baseRect)
  }

  private func shrinkInsertionPointRectToFont(_ rect: NSRect) -> NSRect {
    let caretFont = font ?? .systemFont(ofSize: 14)
    let fontHeight = caretFont.ascender - caretFont.descender
    let centeredGlyphInset = max(0, rect.height - fontHeight) / 2
    return NSRect(
      x: rect.origin.x,
      y: rect.origin.y + centeredGlyphInset,
      width: rect.width,
      height: fontHeight
    )
  }

  private func invalidateInsertionPointRect(_ rect: NSRect) {
    super.setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
    if let lastInsertionPointDisplayRect {
      super.setNeedsDisplay(lastInsertionPointDisplayRect.insetBy(dx: -2, dy: -2))
    }
    lastInsertionPointDisplayRect = nil
  }

  func normalizedInsertionPointRect(_ rect: NSRect) -> NSRect {
    guard let layoutManager, let textContainer else { return rect }
    layoutManager.ensureLayout(for: textContainer)
    let nsString = string as NSString
    guard nsString.length > 0, layoutManager.numberOfGlyphs > 0 else {
      return NSRect(
        x: rect.origin.x,
        y: textContainerOrigin.y,
        width: rect.width,
        height: EditorMetrics.lineHeight
      )
    }
    let cursor = min(selectedRange.location, nsString.length)
    if cursor == nsString.length, cursor > 0, nsString.character(at: cursor - 1) == 0x0A {
      let extra = layoutManager.extraLineFragmentRect
      let originY: CGFloat
      if !extra.isEmpty {
        originY = textContainerOrigin.y + extra.origin.y
      } else {
        let lastGlyphIndex = max(0, layoutManager.numberOfGlyphs - 1)
        let fragment = layoutManager.lineFragmentRect(
          forGlyphAt: lastGlyphIndex,
          effectiveRange: nil
        )
        originY = textContainerOrigin.y + fragment.maxY
      }
      return NSRect(
        x: textContainerOrigin.x + extra.origin.x,
        y: originY,
        width: rect.width,
        height: EditorMetrics.lineHeight
      )
    }
    let characterIndex = insertionPointReferenceCharacter(cursor: cursor, in: nsString)
    let glyphIndex = min(
      layoutManager.glyphIndexForCharacter(at: characterIndex),
      max(0, layoutManager.numberOfGlyphs - 1)
    )
    let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    return NSRect(
      x: insertionPointX(cursor: cursor, glyphIndex: glyphIndex, in: nsString),
      y: textContainerOrigin.y + fragment.origin.y,
      width: rect.width,
      height: fragment.height
    )
  }

  private func insertionPointReferenceCharacter(cursor: Int, in nsString: NSString) -> Int {
    if cursor == nsString.length { return max(0, cursor - 1) }
    if cursor > 0, nsString.character(at: cursor - 1) == 0x0A { return cursor }
    return min(max(0, cursor), nsString.length - 1)
  }

  private func insertionPointX(cursor: Int, glyphIndex: Int, in nsString: NSString) -> CGFloat {
    guard cursor > 0, nsString.character(at: cursor - 1) != 0x0A, let textContainer else {
      let fragment =
        layoutManager?.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil) ?? .zero
      return textContainerOrigin.x + fragment.minX
    }
    let priorGlyph = layoutManager?.glyphIndexForCharacter(at: cursor - 1) ?? glyphIndex
    let priorRect =
      layoutManager?.boundingRect(
        forGlyphRange: NSRange(location: priorGlyph, length: 1),
        in: textContainer
      ) ?? .zero
    return textContainerOrigin.x + priorRect.maxX
  }

  override func setNeedsDisplay(_ invalidRect: NSRect) {
    let dx: CGFloat = vimEngine?.mode == .normal ? -(EditorMetrics.normalModeCursorWidth + 2) : 0
    super.setNeedsDisplay(invalidRect.insetBy(dx: dx, dy: -2))
    if let lastInsertionPointDisplayRect {
      super.setNeedsDisplay(lastInsertionPointDisplayRect.insetBy(dx: dx, dy: -2))
    }
  }

  @objc func insertTodayBadgeToken(_ sender: Any?) {
    insertText("@today", replacementRange: NSRange(location: NSNotFound, length: 0))
  }

  // swiftlint:disable opening_brace
  func normalizeSpecialTokens() -> Bool {
    let original = string
    var updated = original
    var targetSelection = selectedRange
    var renderedToken: RenderedToken?
    let originalNS = original as NSString

    guard let edit = lastEditContext else { return false }
    lastEditContext = nil
    if edit.isPaste { return false }
    pruneSuppressedOccurrences(after: edit, in: originalNS)

    if let replacement = edit.replacement, replacement.count == 1 || replacement == "@today" {
      let caret = selectedRange.location
      if let tokenRange = originalNS.trailingTokenRange("@today", endingAt: caret),
        !isSuppressed(literal: "@today", range: tokenRange, in: originalNS)
      {
        let date = Self.todayDisplayString()
        updated = originalNS.replacingCharacters(in: tokenRange, with: date)
        renderedToken = RenderedToken(
          kind: .today,
          tokenLiteral: "@today",
          reversionText: "@today",
          renderedText: date,
          renderedRange: NSRange(location: tokenRange.location, length: (date as NSString).length)
        )
        targetSelection = NSRange(
          location: tokenRange.location + (date as NSString).length,
          length: 0
        )
      }
    }

    guard updated != original else { return false }
    replaceContentPreservingEditorAttributes(with: updated)
    let clamped = min(targetSelection.location, (updated as NSString).length)
    setInsertionPoint(clamped)
    lastRenderedToken = renderedToken
    return true
  }
  // swiftlint:enable opening_brace

  private static func todayDisplayString() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMMM yyyy"
    return formatter.string(from: Date())
  }

  private func revertLastRenderedTokenIfPossible() -> Bool {
    guard let token = lastRenderedToken else { return false }
    let currentNS = string as NSString
    let max = token.renderedRange.location + token.renderedRange.length
    guard max <= currentNS.length else {
      lastRenderedToken = nil
      return false
    }
    let live = currentNS.substring(with: token.renderedRange)
    guard live == token.renderedText else {
      lastRenderedToken = nil
      return false
    }
    let caret = selectedRange.location
    let originalTokenEnd = token.renderedRange.location + (token.tokenLiteral as NSString).length
    let canRevert =
      selectedRange.length == 0
      && (caret == max || (caret == originalTokenEnd && originalTokenEnd <= currentNS.length))
    guard canRevert else { return false }
    if shouldChangeText(in: token.renderedRange, replacementString: token.reversionText) {
      replaceCharacters(in: token.renderedRange, with: token.reversionText)
      let location = token.renderedRange.location + (token.reversionText as NSString).length
      suppressedOccurrences.append(
        SuppressedTokenOccurrence(
          literal: token.reversionText,
          range: NSRange(
            location: token.renderedRange.location,
            length: (token.reversionText as NSString).length
          )
        )
      )
      setInsertionPoint(location)
      lastRenderedToken = nil
      didChangeText()
      return true
    }
    return false
  }

  private func replaceContentPreservingEditorAttributes(with updated: String) {
    guard let storage = textStorage else {
      string = updated
      return
    }
    let range = NSRange(location: 0, length: storage.length)
    let attributed = NSAttributedString(string: updated, attributes: typingAttributes)
    storage.beginEditing()
    storage.replaceCharacters(in: range, with: attributed)
    storage.endEditing()
    if let textContainer {
      layoutManager?.ensureLayout(for: textContainer)
    }
  }

  private func stabilizeTypingAttributes() {
    guard !editorTextAttributes.isEmpty else { return }
    typingAttributes = editorTextAttributes
  }

  override func copy(_ sender: Any?) {
    if selectedRange.length == 0 {
      super.copy(sender)
      return
    }
    let nsString = string as NSString
    let selected = nsString.substring(with: selectedRange)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(selected, forType: .string)
  }

  private func isSuppressed(literal: String, range: NSRange, in nsString: NSString) -> Bool {
    suppressedOccurrences = suppressedOccurrences.filter { item in
      let max = item.range.location + item.range.length
      guard max <= nsString.length else { return false }
      return nsString.substring(with: item.range) == item.literal
    }
    return suppressedOccurrences.contains {
      $0.literal == literal && NSEqualRanges($0.range, range)
    }
  }

  private func pruneSuppressedOccurrences(after edit: EditContext, in nsString: NSString) {
    suppressedOccurrences = suppressedOccurrences.filter { item in
      let max = item.range.location + item.range.length
      guard max <= nsString.length, nsString.substring(with: item.range) == item.literal else {
        return false
      }
      if edit.replacement == item.literal, edit.range.location == item.range.location {
        return true
      }
      if edit.range.length > 0 {
        return NSIntersectionRange(edit.range, item.range).length == 0
      }
      return edit.range.location <= item.range.location || edit.range.location >= max
    }
  }

  private func setInsertionPoint(_ location: Int) {
    invalidateNormalModeCursorDisplay()
    setSelectedRange(
      NSRange(location: location, length: 0),
      affinity: .downstream,
      stillSelecting: false
    )
    invalidateNormalModeCursorDisplay()
    if vimEngine?.mode == .normal {
      displayIfNeeded()
    }
  }

  private func invalidateNormalModeCursorDisplay() {
    guard vimEngine?.mode == .normal else { return }
    let baseRect = NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    let current = normalModeCursorDisplayRect(for: baseRect, turnedOn: true)
    super.setNeedsDisplay(current.insetBy(dx: -2, dy: -2))
    if let lastInsertionPointDisplayRect {
      super.setNeedsDisplay(lastInsertionPointDisplayRect.insetBy(dx: -2, dy: -2))
    }
  }

  private func normalModeCursorDisplayRect(for rect: NSRect, turnedOn flag: Bool) -> NSRect {
    let displayRect =
      if flag {
        shrinkInsertionPointRectToFont(normalizedInsertionPointRect(rect))
      } else {
        insertionPointDisplayRect(for: rect, turnedOn: false)
      }

    return NSRect(
      x: displayRect.origin.x,
      y: displayRect.origin.y,
      width: max(displayRect.width, EditorMetrics.normalModeCursorWidth),
      height: displayRect.height
    )
  }

}

extension String {
  var matchesDateLine: Bool {
    range(of: #"^\d{1,2}\s+[A-Za-z]+\s+\d{4}$"#, options: .regularExpression) != nil
  }
}

extension NSString {
  func trailingTokenRange(_ token: String, endingAt caret: Int) -> NSRange? {
    let tokenLen = (token as NSString).length
    guard caret >= tokenLen else { return nil }
    let start = caret - tokenLen
    guard start + tokenLen <= length else { return nil }
    let candidate = substring(with: NSRange(location: start, length: tokenLen))
    return candidate == token ? NSRange(location: start, length: tokenLen) : nil
  }

}

// MARK: - SuggestionView

/// Lightweight, layer-free view that draws a single line of text using
/// the editor's font and `LineNumberRuler.synthesizedBaseline`, so the
/// inline math suggestion sits on the exact same baseline as the
/// caret's character row.
final class SuggestionView: NSView {
  var text: String = "" { didSet { needsDisplay = true } }
  var font: NSFont = .systemFont(ofSize: 14) { didSet { needsDisplay = true } }
  var textColor: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func intrinsicTextWidth() -> CGFloat {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    return ceil((text as NSString).size(withAttributes: attrs).width) + 2
  }

  override func draw(_ dirtyRect: NSRect) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
    let baselineInFragment = LineNumberRuler.synthesizedBaseline(
      fragmentHeight: EditorMetrics.lineHeight,
      font: font
    )
    let drawY = baselineInFragment - font.ascender
    (text as NSString).draw(at: NSPoint(x: 0, y: drawY), withAttributes: attrs)
  }
}

// MARK: - FixedLineHeightLayoutManager

/// Forces every line fragment -- including empty paragraphs -- to have
/// identical height and baseline positioning. Without this, empty lines
/// (`\n`) get a different glyph Y offset from `NSLayoutManager`'s
/// default typesetter, causing visually uneven spacing between lines.
final class FixedLineHeightLayoutManager: NSLayoutManager {
  var fixedLineHeight: CGFloat = EditorMetrics.lineHeight
  /// Cached editor font used for baseline centering. Avoids looking up
  /// `at: 0` from storage on every glyph placement, which is fragile
  /// when position 0 falls back to a different font metric than the
  /// editor font.
  var editorFont: NSFont = .systemFont(ofSize: EditorMetrics.fontSize)

  override func setLineFragmentRect(
    _ fragmentRect: NSRect,
    forGlyphRange glyphRange: NSRange,
    usedRect: NSRect
  ) {
    var frag = fragmentRect
    // Derive origin.y from the previously stored rect so the typesetter's
    // internal Y-tracker (which advances by the glyph's *natural* height,
    // not our overridden height) cannot push subsequent lines off-grid.
    // Without this, a substituted-font glyph on line N can cause
    // line N+1 to land at natural_height instead of fixedLineHeight, and
    // the next partial re-layout corrects it — producing the visible shift.
    if glyphRange.location == 0 {
      frag.origin.y = 0
    } else {
      let prevFrag = lineFragmentRect(forGlyphAt: glyphRange.location - 1, effectiveRange: nil)
      if !prevFrag.isEmpty {
        frag.origin.y = prevFrag.maxY
      }
    }
    frag.size.height = fixedLineHeight
    var used = usedRect
    used.origin.y = frag.origin.y
    used.size.height = fixedLineHeight
    super.setLineFragmentRect(frag, forGlyphRange: glyphRange, usedRect: used)
  }

  override func setExtraLineFragmentRect(
    _ fragmentRect: NSRect,
    usedRect: NSRect,
    textContainer: NSTextContainer
  ) {
    var frag = fragmentRect
    var used = usedRect
    if numberOfGlyphs > 0 {
      let lastFrag = lineFragmentRect(forGlyphAt: numberOfGlyphs - 1, effectiveRange: nil)
      if !lastFrag.isEmpty {
        frag.origin.y = lastFrag.maxY
        used.origin.y = frag.origin.y
      }
    }
    frag.size.height = fixedLineHeight
    used.size.height = fixedLineHeight
    super.setExtraLineFragmentRect(frag, usedRect: used, textContainer: textContainer)
  }

  override func setLocation(
    _ location: NSPoint,
    forStartOfGlyphRange glyphRange: NSRange
  ) {
    let naturalHeight = editorFont.ascender - editorFont.descender
    let fixedY = editorFont.ascender + (fixedLineHeight - naturalHeight) / 2
    super.setLocation(
      NSPoint(x: location.x, y: fixedY),
      forStartOfGlyphRange: glyphRange
    )
  }

}
