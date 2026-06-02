import SwiftUI

struct VimStatusLine: View {
  let theme: Theme
  let currentText: String
  let mode: VimMode
  let prompt: VimController.Prompt?
  let message: VimController.Message?
  let searchStatus: String?
  let hasOverlayBelow: Bool
  let height: CGFloat

  var body: some View {
    HStack(spacing: 0) {
      if let prompt {
        statusModeSegment(label: promptStatusLabel(for: prompt.kind), mode: mode)
        HStack(spacing: 0) {
          VimPromptView(prompt: prompt, theme: theme)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(statusTrailingFill)
      } else {
        statusModeSegment(label: shortLabel(for: mode), mode: mode)
        Text(noteFileLabel)
          .font(.custom("MonoLisa", size: 16).weight(.bold))
          .tracking(0.4)
          .foregroundStyle(theme.text.opacity(0.94))
          .lineLimit(1)
          .truncationMode(.middle)
          .padding(.horizontal, 12)
          .frame(height: height)
          .background(statusFileFill)
        HStack(spacing: 10) {
          Spacer(minLength: 0)
          statusTrailingText
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(statusTrailingFill)
      }
    }
    .frame(height: height)
    .clipShape(barShape)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(theme.border.opacity(0.45))
        .frame(height: 1)
    }
    .overlay(barShape.strokeBorder(theme.border.opacity(0.55), lineWidth: 1))
  }

  private var barShape: UnevenRoundedRectangle {
    let roundBottom = !hasOverlayBelow
    return UnevenRoundedRectangle(
      topLeadingRadius: 0,
      bottomLeadingRadius: roundBottom ? 10 : 0,
      bottomTrailingRadius: roundBottom ? 10 : 0,
      topTrailingRadius: 0,
      style: .continuous
    )
  }

  @ViewBuilder
  private var statusTrailingText: some View {
    if let message {
      Text(message.text)
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundStyle(messageColor(for: message.kind))
        .lineLimit(1)
        .truncationMode(.tail)
    } else if let searchStatus {
      Text(searchStatus)
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundStyle(theme.text.opacity(0.58))
        .lineLimit(1)
    }
  }

  private func statusModeSegment(label: String, mode: VimMode) -> some View {
    Text(label)
      .font(.system(size: 20, weight: .black, design: .monospaced))
      .foregroundStyle(statusModeText(for: mode))
      .frame(width: 46, height: height)
      .background(statusModeFill(for: mode))
  }

  private func shortLabel(for mode: VimMode) -> String {
    switch mode {
    case .normal: return "N"
    case .insert: return "I"
    case .visualLine: return "V"
    }
  }

  private func promptStatusLabel(for kind: VimController.PromptKind) -> String {
    switch kind {
    case .command: return ":"
    case .search: return "/"
    case .flash(_, _, let scope): return scope == .currentLine ? "F" : "S"
    case .lineFlash: return "K"
    }
  }

  private var noteFileLabel: String {
    let firstLine =
      currentText
      .split(whereSeparator: { $0.isNewline })
      .map(String.init)
      .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let raw = firstLine ?? "SpotNote"
    let stripped =
      raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "#*-_` []()"))
    let words = stripped.isEmpty ? ["SpotNote"] : stripped.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let base = words.joined(separator: "-").uppercased()
    let clipped = base.count > 18 ? String(base.prefix(18)) : base
    return "\(clipped).md"
  }

  private var statusFileFill: Color {
    theme.mode == .dark
      ? Color(red: 0.26, green: 0.28, blue: 0.38).opacity(0.90)
      : Color.black.opacity(0.10)
  }

  private var statusTrailingFill: Color {
    theme.mode == .dark
      ? Color(red: 0.33, green: 0.36, blue: 0.47).opacity(0.88)
      : Color.black.opacity(0.07)
  }

  private func statusModeFill(for mode: VimMode) -> Color {
    switch mode {
    case .normal: return Color(red: 0.55, green: 0.69, blue: 0.98)
    case .insert: return Color(red: 0.65, green: 0.89, blue: 0.63)
    case .visualLine: return Color(red: 0.80, green: 0.67, blue: 0.94)
    }
  }

  private func statusModeText(for mode: VimMode) -> Color {
    switch mode {
    case .normal: return Color(red: 0.07, green: 0.10, blue: 0.18)
    case .insert: return Color(red: 0.06, green: 0.13, blue: 0.08)
    case .visualLine: return Color(red: 0.13, green: 0.08, blue: 0.18)
    }
  }

  private func messageColor(for kind: VimController.MessageKind) -> Color {
    switch kind {
    case .info: return theme.text.opacity(0.7)
    case .success: return Color(red: 0.40, green: 0.78, blue: 0.50)
    case .error: return Color(red: 0.95, green: 0.45, blue: 0.45)
    }
  }
}

enum VimPromptDisplay {
  static func prefix(for kind: VimController.PromptKind) -> String {
    switch kind {
    case .command: return ":"
    case .search: return "/"
    case .flash(_, let count, _): return count > 1 ? "\(count)⚡ " : "⚡ "
    case .lineFlash(let count): return count > 1 ? "\(count)K" : "K"
    }
  }
}

private struct VimPromptView: View {
  let prompt: VimController.Prompt
  let theme: Theme

  var body: some View {
    HStack(spacing: 0) {
      Text(prefix)
        .foregroundStyle(theme.text.opacity(0.85))
      Text(prompt.buffer)
        .foregroundStyle(theme.text)
      TimelineView(.periodic(from: .now, by: 0.55)) { context in
        let visible = Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
        Text("▏")
          .foregroundStyle(theme.text.opacity(visible ? 0.95 : 0))
      }
    }
    .font(.system(size: 13, weight: .regular, design: .monospaced))
    .lineLimit(1)
    .truncationMode(.head)
  }

  private var prefix: String {
    VimPromptDisplay.prefix(for: prompt.kind)
  }
}
