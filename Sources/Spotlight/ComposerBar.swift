import SwiftUI

/// Bottom capsule bar inside the card, in the SlashNote composer layout:
/// checklist glyph, prompt field, mic and send circles. Submitting appends the
/// draft to the note as a fresh `- ` bullet; mic is a visual placeholder until
/// voice input exists and stays disabled.
struct ComposerBar: View {
  let theme: Theme
  let onSubmit: (String) -> Void

  @State private var draft: String = ""
  @FocusState private var focused: Bool

  /// Send-button accent sampled from the SlashNote app renders.
  private static let sendAccent = Color(red: 99 / 255, green: 170 / 255, blue: 233 / 255)

  private var controlFill: Color {
    theme.mode == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
  }

  private var hasDraft: Bool {
    !draft.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "checklist")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(theme.text.opacity(0.45))
      TextField("What to write?", text: $draft)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(theme.text)
        .focused($focused)
        .onSubmit(submit)
      Image(systemName: "mic.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(theme.text.opacity(0.25))
        .frame(width: 24, height: 24)
        .background(Circle().fill(controlFill))
        .help("Voice input is not wired up yet")
      Button(action: submit) {
        Image(systemName: "arrow.up")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(hasDraft ? Color.white : theme.text.opacity(0.30))
          .frame(width: 24, height: 24)
          .background(Circle().fill(hasDraft ? Self.sendAccent : controlFill))
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(!hasDraft)
      .help("Append to note")
    }
    .padding(.leading, 12)
    .padding(.trailing, 6)
    .frame(height: 32)
    .background(Capsule(style: .continuous).fill(controlFill))
    .overlay(Capsule(style: .continuous).strokeBorder(theme.border, lineWidth: 1))
    .padding(.horizontal, 10)
    .frame(height: EditorMetrics.composerHeight, alignment: .top)
  }

  private func submit() {
    guard hasDraft else { return }
    onSubmit(draft.trimmingCharacters(in: .whitespaces))
    draft = ""
  }
}
