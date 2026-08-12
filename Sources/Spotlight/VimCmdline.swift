import SwiftUI

/// vim's cmdline in the bottom bar -- the `/` and `:` prompt surface.
/// Aligned to the editor's text column and set in the editor's own
/// mono face at the editor's size (David 2026-08-11: "align the
/// searchbar with the main editor text... make it the same size as
/// the text itself"): the query IS note text, so it wears the note's
/// type and ink; only the sigil (his flash.lua's bolt for `/`, a
/// chevron for `:`) sits in the chrome's counter gray. Nothing renders
/// outside an open prompt -- no count, no residue (the bands are the
/// feedback).
///
/// Until this surface existed, `/` and `:` were typed BLIND (no view
/// rendered `prompt.buffer` or `searchStatus`).
struct VimCmdline: View {
  @ObservedObject var controller: VimController
  let theme: Theme
  let isKey: Bool

  var body: some View {
    Group {
      if let prompt = controller.prompt, let sigil = Self.sigil(for: prompt.kind) {
        line(sigil: sigil, buffer: prompt.buffer)
      }
    }
    .opacity(isKey ? 1 : 0.45)
    .animation(.spring(response: 0.2, dampingFraction: 0.85), value: controller.prompt)
    .animation(.easeOut(duration: 0.12), value: isKey)
  }

  /// Only the typed prompts render here; flash/word-hint prompts draw
  /// their UI inside the editor.
  static func sigil(for kind: VimController.PromptKind) -> String? {
    switch kind {
    case .search: return "bolt.fill"
    case .command: return "chevron.right"
    default: return nil
    }
  }

  /// The sigil lives IN the 37pt gutter (nvim's `/` occupies the column
  /// before text), right-hugging the text column with its BASELINE on
  /// the query's baseline, so the query's first glyph lands exactly on
  /// the editor's text column with the sigil optically seated. No match
  /// count anywhere (David 2026-08-11: "i don't need the count") -- the
  /// bands are the feedback.
  private func line(sigil: String, buffer: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Image(systemName: sigil)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(RaycastChromePalette.counter)
        .padding(.trailing, 8)
        .frame(width: EditorMetrics.textLeadingGap, alignment: .trailing)
      if !buffer.isEmpty {
        Text(buffer)
          .font(Self.queryFont)
          .foregroundStyle(theme.text)
          .lineLimit(1)
          .truncationMode(.head)
          .layoutPriority(-1)
      }
      caretBar
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
        .padding(.leading, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .transition(.opacity)
    .accessibilityLabel("Vim prompt: \(buffer)")
  }

  /// The cmdline is a rendered echo (keys route through the editor),
  /// so it draws its own thin insert-style caret.
  private var caretBar: some View {
    RoundedRectangle(cornerRadius: 1)
      .fill((theme.cursor ?? theme.headingText).opacity(0.9))
      .frame(width: 2, height: 24)
  }

  /// The editor's face at the editor's size: the query reads as note
  /// text. NSFont is toll-free bridged to CTFont, so the bundle
  /// fallback logic in `SpotNoteFont` carries over.
  private static var queryFont: Font {
    Font(SpotNoteFont.editor() as CTFont)
  }
}

/// Composes the chrome bottom bar with the vim surfaces: the centered
/// character counter yields to the cmdline while a prompt is open
/// (both would otherwise collide mid-bar), and the mode badge rides
/// the trailing T-button slot. Observes the controller HERE so the
/// root view does not re-render per keystroke.
struct VimAwareBottomBar: View {
  @ObservedObject var controller: VimController
  let characterCount: Int
  let theme: Theme
  let isKey: Bool

  var body: some View {
    RaycastBottomBar(characterCount: characterCount)
      .opacity(controller.prompt == nil ? 1 : 0)
      .animation(.easeOut(duration: 0.12), value: controller.prompt == nil)
      .overlay(alignment: .leading) {
        VimCmdline(controller: controller, theme: theme, isKey: isKey)
          .padding(.trailing, 56)
      }
      .overlay(alignment: .trailing) {
        VimModeBadge(controller: controller, isKey: isKey)
          .padding(.trailing, 9)
      }
  }
}
