import AppKit
import Testing

@testable import Spotlight

/// Crash-hunt harness: drive the FULL keyDown path through visual-mode
/// sequences over edge-case documents. Any range trap / NSException
/// kills the test runner -- that is the signal.
@MainActor
extension MultilineEditorVimLogicalLineMotionTests {
  private func armed(_ text: String, caret: Int) -> PlaceholderTextView {
    let textView = makeVimMotionTextView(text: text)
    textView.vimModeEnabled = true
    textView.attachVimController(VimController())
    textView.vimPasteboard = NSPasteboard(name: NSPasteboard.Name("visual-stress"))
    textView.setSelectedRange(NSRange(location: min(caret, (text as NSString).length), length: 0))
    return textView
  }

  private func type(_ textView: PlaceholderTextView, _ keys: [(String, UInt16)]) {
    for (ch, code) in keys {
      let mods: NSEvent.ModifierFlags = ch.first.map { $0.isUppercase || "$^".contains($0) } == true ? [.shift] : []
      textView.keyDown(with: keyEvent(characters: ch, ignoring: ch, keyCode: code, modifiers: mods))
    }
  }

  private static let docs: [String] = [
    "",
    "a",
    "hello world",
    "alpha\nbravo\ncharlie",
    "trailing\n",
    "\n\n\n",
    "- bullet one\n- bullet two\n  continuation",
    "word"
  ]

  @Test("visual stress: v + motions + operators never trap")
  func visualStressCharwise() {
    let sequences: [[(String, UInt16)]] = [
      [("v", 9), ("l", 37), ("l", 37), ("d", 2)],
      [("v", 9), ("e", 14), ("y", 16)],
      [("v", 9), ("$", 21), ("d", 2)],
      [("v", 9), ("j", 38), ("j", 38), ("c", 8)],
      [("v", 9), ("k", 40), ("x", 7)],
      [("v", 9), ("w", 13), ("w", 13), ("y", 16)],
      [("v", 9), ("G", 5), ("d", 2)],
      [("v", 9), ("g", 5), ("g", 5), ("y", 16)],
      [("v", 9), ("0", 29), ("d", 2)],
      [("v", 9), ("b", 11), ("c", 8)],
      [("v", 9), ("2", 19), ("j", 38), ("d", 2)],
      [("v", 9), ("\u{1B}", 53), ("v", 9), ("l", 37), ("v", 9)],
      [("v", 9), ("V", 9), ("j", 38), ("d", 2)],
      [("V", 9), ("j", 38), ("y", 16)],
      [("V", 9), ("k", 40), ("c", 8)],
      [("V", 9), ("G", 5), ("d", 2)],
      [("V", 9), ("v", 9), ("l", 37), ("y", 16)],
      [("v", 9), ("h", 4), ("h", 4), ("d", 2)]
    ]
    for doc in Self.docs {
      let length = (doc as NSString).length
      for caret in [0, length / 2, max(0, length - 1), length] {
        for seq in sequences {
          let textView = armed(doc, caret: caret)
          type(textView, seq)
          let ns = textView.string as NSString
          #expect(textView.selectedRange.location + textView.selectedRange.length <= ns.length)
          if let engine = textView.vimEngine, engine.mode == .insert {
            _ = textView.vimEngine  // insert after c is legal
          }
        }
      }
    }
  }
}
