import SwiftUI

/// Theme picker as a Raycast-style floating modal (replaces the old
/// bottom-bar "T" popover). Rows preview each theme's surface color.
struct RaycastThemesModal: View {
  @ObservedObject var preferences: ThemePreferences
  let onClose: () -> Void

  var body: some View {
    RaycastModalSheet {
      VStack(alignment: .leading, spacing: 0) {
        Text("Theme")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(RaycastModalPalette.secondaryText)
          .padding(.horizontal, 16)
          .padding(.top, 14)
          .padding(.bottom, 6)
        list
      }
      .padding(.bottom, 8)
    }
  }

  private var list: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(ThemeCatalog.all) { theme in
          row(theme)
        }
      }
      .padding(.horizontal, 8)
    }
    .frame(maxHeight: 340)
  }

  private func row(_ theme: Theme) -> some View {
    let isSelected = preferences.selectedThemeID == theme.id
    return Button {
      preferences.selectedThemeID = theme.id
      onClose()
    } label: {
      HStack(spacing: 10) {
        Circle()
          .fill(theme.background)
          .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
          .frame(width: 14, height: 14)
        Text(theme.name)
          .font(.system(size: 14))
          .foregroundStyle(RaycastModalPalette.primaryText)
        Spacer(minLength: 12)
        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(RaycastModalPalette.secondaryText)
        }
      }
      .padding(.horizontal, 8)
      .frame(height: 38)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? RaycastModalPalette.selectedRow : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
