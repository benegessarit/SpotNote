import AppKit
import Foundation
import Testing

@testable import Spotlight

@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {
  @Test("line comment beginning with // is tokenized")
  func lineCommentSlash() {
    let tokens = SyntaxHighlighter.tokens(in: "let x = 1 // trailing", language: "swift")
    #expect(tokens.contains { $0.category == .comment })
  }

  @Test("hash-style comment is tokenized")
  func hashComment() {
    let tokens = SyntaxHighlighter.tokens(in: "x = 1  # note", language: "python")
    #expect(tokens.contains { $0.category == .comment })
  }

  @Test("double-quoted strings are tokenized as strings")
  func doubleQuotedString() {
    let tokens = SyntaxHighlighter.tokens(in: "let s = \"hello world\"", language: "swift")
    #expect(tokens.contains { $0.category == .string })
  }

  @Test("integers and floats are tokenized as numbers")
  func numbers() {
    let tokens = SyntaxHighlighter.tokens(in: "let n = 42 + 3.14", language: "swift")
    let numberCount = tokens.filter { $0.category == .number }.count
    #expect(numberCount == 2)
  }

  @Test("language-specific keywords are flagged only for that language")
  func languageSpecificKeywords() {
    let swift = SyntaxHighlighter.tokens(in: "func f() {}", language: "swift")
    let python = SyntaxHighlighter.tokens(in: "func f() {}", language: "python")
    // `func` is a Swift keyword but NOT a Python one.
    #expect(swift.contains { $0.category == .keyword })
    #expect(!python.contains { $0.category == .keyword })
  }

  @Test("unknown languages fall back to a common keyword set")
  func fallbackKeywords() {
    let tokens = SyntaxHighlighter.tokens(in: "if x return", language: "unknown-lang")
    let keywords = tokens.filter { $0.category == .keyword }.count
    #expect(keywords >= 2, "both 'if' and 'return' should hit the fallback set")
  }

  @Test("identifiers not in any keyword set produce no token")
  func nonKeywordIdentifierIgnored() {
    let tokens = SyntaxHighlighter.tokens(in: "myValue other", language: nil)
    #expect(tokens.isEmpty)
  }

  @Test("splitLanguage recognizes the language on the first line")
  func splitLanguageRecognized() {
    let input = "swift\nlet x = 1\n"
    let split = SyntaxHighlighter.splitLanguage(from: input)
    #expect(split.language == "swift")
    #expect(split.code == "let x = 1\n")
  }

  @Test("splitLanguage returns nil when no tag is present")
  func splitLanguageAbsent() {
    let input = "let x = 1\n"
    let split = SyntaxHighlighter.splitLanguage(from: input)
    #expect(split.language == nil)
    #expect(split.code == input)
  }

  @Test("comment tokens extend to end of line but not past it")
  func lineCommentBounded() {
    let tokens = SyntaxHighlighter.tokens(in: "a // first\nb + 1", language: "swift")
    let comments = tokens.filter { $0.category == .comment }
    #expect(comments.count == 1)
    // The number `1` on the next line should still be tokenized.
    #expect(tokens.contains { $0.category == .number })
  }
}

@MainActor
@Suite("CodeStyler Markdown visual styling")
struct CodeStylerVisualTests {
  @Test("Markdown headings are visibly bolded without changing stored text")
  func markdownHeadingsAreVisiblyBold() throws {
    let text = "plain\n## Tray\nnext"
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    textView.font = SpotNoteFont.editor()
    textView.string = text

    CodeStyler.apply(to: textView, theme: ThemeCatalog.obsidian)

    let headingFont = try #require(storageFont(at: lineStart(1, in: text), in: textView))
    let bodyFont = try #require(storageFont(at: 0, in: textView))

    #expect(NSFontManager.shared.traits(of: headingFont).contains(.boldFontMask))
    #expect(!NSFontManager.shared.traits(of: bodyFont).contains(.boldFontMask))
    #expect(textView.textStorage?.string == text)
  }

  @Test("Markdown headings use a brighter storage foreground than body text")
  func markdownHeadingsUseBrighterStorageForeground() throws {
    let theme = ThemeCatalog.mirage
    let text = "plain\n## To Do\nnext"
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    textView.font = SpotNoteFont.editor()
    textView.string = text
    textView.textStorage?.addAttribute(
      .foregroundColor,
      value: NSColor(theme.text),
      range: NSRange(location: 0, length: (text as NSString).length)
    )

    CodeStyler.apply(to: textView, theme: theme)

    let bodyColor = try #require(storageColor(at: 0, in: textView)?.usingColorSpace(.sRGB))
    let headingColor = try #require(
      storageColor(at: lineStart(1, in: text), in: textView)?.usingColorSpace(.sRGB)
    )

    #expect(headingColor != bodyColor)
    #expect(relativeLuminance(of: headingColor) > relativeLuminance(of: bodyColor))
    #expect(textView.textStorage?.string == text)
  }

  @Test("Markdown-looking headings inside fenced code are not bolded")
  func headingsInsideFencedCodeAreIgnored() {
    let text = "```\n## not a heading\n```\n## Tray"
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text

    CodeStyler.apply(to: textView, theme: ThemeCatalog.obsidian)

    let fencedFont = storageFont(at: lineStart(1, in: text), in: textView)
    let headingFont = storageFont(at: lineStart(3, in: text), in: textView)

    #expect(fencedFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == false)
    #expect(headingFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true)
  }

  private func storageFont(at location: Int, in textView: NSTextView) -> NSFont? {
    textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
  }

  private func storageColor(at location: Int, in textView: NSTextView) -> NSColor? {
    textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
  }

  private func relativeLuminance(of color: NSColor) -> CGFloat {
    0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
  }

  private func lineStart(_ index: Int, in text: String) -> Int {
    guard index > 0 else { return 0 }
    let lines = text.components(separatedBy: "\n")
    let prefix = lines.prefix(index).joined(separator: "\n")
    return (prefix as NSString).length + 1
  }
}
