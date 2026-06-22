import AppKit
import Testing

@testable import Spotlight

@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  func makeVimMotionTextView(
    text: String,
    checklistLines: [Int: ChecklistLineState] = [:],
    width: CGFloat = EditorMetrics.panelWidth
  ) -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: width, height: 240))
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

  func makeScrollableVimMotionTextView(text: String) -> PlaceholderTextView {
    let textView = makeVimMotionTextView(text: text)
    let lineCount = CGFloat(max(1, text.components(separatedBy: "\n").count))
    textView.frame = NSRect(
      x: 0,
      y: 0,
      width: EditorMetrics.panelWidth,
      height: EditorMetrics.lineHeight * lineCount
    )
    return textView
  }

  func makeScrollView(containing textView: PlaceholderTextView) -> NSScrollView {
    let scrollView = NSScrollView(
      frame: NSRect(
        x: 0,
        y: 0,
        width: EditorMetrics.panelWidth,
        height: EditorMetrics.lineHeight * 5
      )
    )
    scrollView.documentView = textView
    return scrollView
  }

  func lineStart(_ index: Int, in text: String) -> Int {
    guard index > 0 else { return 0 }
    let lines = text.components(separatedBy: "\n")
    let prefix = lines.prefix(index).joined(separator: "\n")
    return (prefix as NSString).length + 1
  }

  func temporaryForegroundColor(at location: Int, in textView: PlaceholderTextView) -> NSColor? {
    textView.layoutManager?.temporaryAttributes(
      atCharacterIndex: location,
      effectiveRange: nil
    )[.foregroundColor] as? NSColor
  }

  func colorComponents(_ color: NSColor?) -> [CGFloat] {
    guard let color = color?.usingColorSpace(.deviceRGB) else { return [] }
    return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
  }

  func makeBitmapRep() throws -> NSBitmapImageRep {
    let rep = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 80,
        pixelsHigh: 80,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 80, height: 80).fill()
    return rep
  }

  func drawCursor(
    for textView: PlaceholderTextView,
    in rect: NSRect,
    turnedOn: Bool,
    rep: NSBitmapImageRep
  ) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    textView.drawInsertionPoint(in: rect, color: .clear, turnedOn: turnedOn)
  }

  func bitmapContainsMirageCursor(_ rep: NSBitmapImageRep) -> Bool {
    for y in 0..<rep.pixelsHigh {
      for x in 0..<rep.pixelsWide {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        let isCursorPixel =
          color.redComponent > 0.60 && color.greenComponent > 0.45 && color.blueComponent > 0.75
          && color.alphaComponent > 0.20
        if isCursorPixel {
          return true
        }
      }
    }
    return false
  }

  func keyEvent(
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
