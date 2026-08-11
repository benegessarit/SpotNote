import SwiftUI

/// The `/` and `:` prompt surface -- a keycap-family capsule in the
/// bottom bar's LEADING slot, the SpotNote analogue of David's flash
/// prompt (his flash.lua floats a ⚡-prefixed strip at the editor's
/// bottom-left; row -1, col 0). Not a command bar: it is the mode
/// pill's sibling -- same hollow ring, same chip chrome -- that exists
/// only while a prompt is open, then collapses to a small counter
/// residue while a search is live.
///
/// Until this view existed, `/` and `:` were typed BLIND (no view
/// rendered `prompt.buffer` or `searchStatus`).
struct VimPromptCapsule: View {
  @ObservedObject var controller: VimController
  let isKey: Bool

  var body: some View {
    Group {
      if let prompt = controller.prompt, let glyph = Self.glyph(for: prompt.kind) {
        capsule(glyph: glyph, buffer: prompt.buffer, count: countText(for: prompt.kind))
      } else if let status = controller.searchStatus {
        residue(status)
      }
    }
    .opacity(isKey ? 1 : 0.45)
    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: controller.prompt)
    .animation(.easeOut(duration: 0.12), value: isKey)
  }

  /// Only the typed prompts render here; flash/word-hint prompts draw
  /// their UI inside the editor.
  static func glyph(for kind: VimController.PromptKind) -> String? {
    switch kind {
    case .search: return "bolt.fill"
    case .command: return "chevron.right"
    default: return nil
    }
  }

  private func countText(for kind: VimController.PromptKind) -> String? {
    kind == .search ? controller.searchStatus : nil
  }

  private func capsule(glyph: String, buffer: String, count: String?) -> some View {
    HStack(spacing: 6) {
      Image(systemName: glyph)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Self.tint)
      Text(buffer.isEmpty ? " " : buffer)
        .font(RaycastFont.regular(13))
        .foregroundStyle(RaycastModalPalette.primaryText)
        .lineLimit(1)
        .truncationMode(.head)
      if let count {
        Text(count)
          .font(RaycastFont.regular(12))
          .foregroundStyle(RaycastModalPalette.secondaryInk)
      }
    }
    .padding(.horizontal, 9)
    .frame(height: 26)
    .frame(maxWidth: 300, alignment: .leading)
    .fixedSize(horizontal: true, vertical: false)
    .background(
      RoundedRectangle(cornerRadius: 5.5, style: .continuous)
        .strokeBorder(Self.tint.opacity(0.35), lineWidth: 1)
    )
    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
    .accessibilityLabel("Vim prompt: \(buffer)")
  }

  /// After Enter: the query goes away, the live counter stays as a
  /// quiet residue until the search clears.
  private func residue(_ status: String) -> some View {
    Text(status)
      .font(RaycastFont.regular(12))
      .foregroundStyle(RaycastModalPalette.secondaryInk)
      .frame(height: 26)
      .transition(.opacity)
      .accessibilityLabel("Search matches: \(status)")
  }

  /// The normal-mode blue -- searching is a normal-mode act.
  static let tint = Color(red: 0x64 / 255, green: 0xA1 / 255, blue: 0xF1 / 255)
}
