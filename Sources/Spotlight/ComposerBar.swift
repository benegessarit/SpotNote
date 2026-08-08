import SwiftUI

/// Bottom capsule bar inside the card, in the SlashNote composer layout but
/// built from native macOS 26 components: a Liquid Glass capsule field with
/// glass mic/send circles, like the Messages compose bar. Submitting appends
/// the draft to the note as a fresh `- ` bullet; mic stays a disabled
/// placeholder until voice input exists.
struct ComposerBar: View {
  let theme: Theme
  let onSubmit: (String) -> Void

  @State private var draft: String = ""
  @FocusState private var focused: Bool

  /// Send-button accent sampled from the SlashNote app renders.
  private static let sendAccent = Color(red: 99 / 255, green: 170 / 255, blue: 233 / 255)

  private var hasDraft: Bool {
    !draft.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "checklist")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
      TextField("What to write?", text: $draft)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(theme.text)
        .focused($focused)
        .onSubmit(submit)
      Image(systemName: "mic.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.tertiary)
        .frame(width: 24, height: 24)
        .help("Voice input is not wired up yet")
      Button(action: submit) {
        Image(systemName: "arrow.up")
          .font(.system(size: 11, weight: .bold))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.glassProminent)
      .buttonBorderShape(.circle)
      .tint(Self.sendAccent)
      .disabled(!hasDraft)
      .help("Append to note")
    }
    .padding(.leading, 12)
    .padding(.trailing, 4)
    .frame(height: 32)
    .glassEffect()
    .padding(.horizontal, 10)
    .frame(height: EditorMetrics.composerHeight, alignment: .top)
  }

  private func submit() {
    guard hasDraft else { return }
    onSubmit(draft.trimmingCharacters(in: .whitespaces))
    draft = ""
  }
}
