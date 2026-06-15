import AppKit
import SwiftUI

struct HermesToastView: View {
  let message: VimController.Message
  let theme: Theme

  private var accent: Color {
    switch message.kind {
    case .info: return theme.placeholder.opacity(0.95)
    case .success: return Color(red: 0.651, green: 0.890, blue: 0.631)
    case .error: return Color(red: 0.953, green: 0.545, blue: 0.659)
    }
  }

  private var fill: Color {
    theme.mode == .dark ? Color.black.opacity(0.42) : Color.white.opacity(0.82)
  }

  var body: some View {
    HStack(spacing: 8) {
      if message.icon == .hermes {
        HermesLogo(color: accent)
      }
      Text(message.text)
        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
        .tracking(0.16)
        .foregroundStyle(accent)
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(fill)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
    )
  }
}

private struct HermesLogo: View {
  let color: Color

  var body: some View {
    Group {
      if let image = Self.image() {
        Image(nsImage: image)
          .resizable()
          .renderingMode(.template)
          .interpolation(.high)
      } else {
        Image(systemName: "sparkles")
          .resizable()
          .scaledToFit()
      }
    }
    .foregroundStyle(color)
    .frame(width: 23, height: 23)
  }

  private static func image() -> NSImage? {
    Bundle.spotlightResources
      .url(forResource: "HermesLogo", withExtension: "png")
      .flatMap { NSImage(contentsOf: $0) }
  }
}
