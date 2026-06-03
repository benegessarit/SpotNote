import Foundation

enum TextObjectOperation { case change, delete }
enum TextObjectScope { case inner, around }

extension VimEngine {
  func pendingTextObjectAction(
    key: String,
    operation: TextObjectOperation,
    scope: TextObjectScope
  ) -> VimAction {
    guard let object = textObject(for: key, scope: scope) else { return .none }
    switch operation {
    case .change:
      setMode(.insert)
      return .changeTextObject(object)
    case .delete:
      return .deleteTextObject(object)
    }
  }

  private func textObject(for key: String, scope: TextObjectScope) -> TextObject? {
    switch (scope, key) {
    case (.inner, "w"): return .innerWord
    case (.around, "w"): return .aroundWord
    case (.inner, "s"): return .innerSentence
    case (.around, "s"): return .aroundSentence
    case (.inner, "p"): return .innerParagraph
    case (.around, "p"): return .aroundParagraph
    default: return nil
    }
  }
}
