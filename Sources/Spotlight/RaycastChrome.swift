import AppKit
import SwiftUI

/// Shared palette for the Raycast Notes shell chrome. These greys are part
/// of the shell identity (pixel-sampled from the live Raycast Beta Notes
/// window) and intentionally do not follow the editor theme.
enum RaycastChromePalette {
  static let closeRed = Color(red: 0xEC / 255, green: 0x67 / 255, blue: 0x65 / 255)
  static let inactiveDot = Color(red: 0x46 / 255, green: 0x48 / 255, blue: 0x56 / 255)
  static let titleKey = Color(red: 0x8C / 255, green: 0x90 / 255, blue: 0xA6 / 255)
  static let titleResigned = Color(red: 0x46 / 255, green: 0x4A / 255, blue: 0x5B / 255)
  static let counter = Color(red: 0x48 / 255, green: 0x4C / 255, blue: 0x5B / 255)
  static let control = Color(red: 0x76 / 255, green: 0x7D / 255, blue: 0x91 / 255)
}

/// Raycast Notes draws its own traffic lights: 14pt dots at 23pt centers,
/// close active red (with an x on hover), minimize/zoom rendered as
/// disabled grey dots. Only close is interactive.
struct RaycastTrafficLights: View {
  let onClose: () -> Void
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 9) {
      Button(action: onClose) {
        ZStack {
          Circle()
            .fill(RaycastChromePalette.closeRed)
          if hovering {
            Image(systemName: "xmark")
              .font(.system(size: 8, weight: .heavy))
              .foregroundStyle(Color.black.opacity(0.55))
          }
        }
        .frame(width: 14, height: 14)
        .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help("Close")
      Circle()
        .fill(RaycastChromePalette.inactiveDot)
        .frame(width: 14, height: 14)
      Circle()
        .fill(RaycastChromePalette.inactiveDot)
        .frame(width: 14, height: 14)
    }
    .onHover { hovering = $0 }
  }
}

/// The Raycast Notes note-switcher glyph: two fanned cards, the front card
/// knocking out the back card's stroke where they overlap. Not in the
/// public @raycast/icons set, so it is drawn directly.
struct RaycastStackedCardsIcon: View {
  var body: some View {
    ZStack {
      backCard
        .stroke(style: strokeStyle)
        .frame(width: 9.5, height: 11.5)
        .rotationEffect(.degrees(-4))
        .offset(x: -2.2, y: 1.6)
      backCard
        .fill(Color.black)
        .frame(width: 9.5, height: 11.5)
        .rotationEffect(.degrees(10))
        .offset(x: 1.8, y: -1.2)
        .blendMode(.destinationOut)
      backCard
        .stroke(style: strokeStyle)
        .frame(width: 9.5, height: 11.5)
        .rotationEffect(.degrees(10))
        .offset(x: 1.8, y: -1.2)
    }
    .compositingGroup()
    .frame(width: 16, height: 16)
  }

  private var backCard: RoundedRectangle {
    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
  }

  private var strokeStyle: StrokeStyle {
    StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
  }
}

/// Loads a bundled Raycast icon rasterized from the exact @raycast/icons
/// path data, tinted at render time via template mode.
private func raycastIconImage(_ resource: String) -> NSImage {
  let bundle = Bundle.spotlightResources
  guard let url = bundle.url(forResource: resource, withExtension: "png"),
    let image = NSImage(contentsOf: url)
  else {
    return NSImage()
  }
  image.isTemplate = true
  return image
}

/// Raycast Notes-style title bar: custom traffic lights at the leading
/// edge, the note's first line centered as the title, and a trailing
/// capsule holding the shortcut, note-switcher, and new-note buttons.
/// Everything but the title hides when the panel is not key, matching
/// Raycast Notes' resigned state.
struct RaycastTopBar: View {
  let title: String
  let theme: Theme
  let isKey: Bool
  let onClose: () -> Void
  let onShowShortcuts: () -> Void
  let onToggleNotes: () -> Void
  let onNewNote: () -> Void
  @Binding var shortcutsShown: Bool

  /// Width reserved at the leading edge for the traffic lights.
  static let trafficLightGutter: CGFloat = 90

  private static let commandIcon = raycastIconImage("RaycastCommandSymbol")
  private static let plusIcon = raycastIconImage("RaycastPlus")

  var body: some View {
    ZStack {
      Text(title)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(
          isKey ? RaycastChromePalette.titleKey : RaycastChromePalette.titleResigned
        )
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Self.trafficLightGutter + 30)
      HStack {
        RaycastTrafficLights(onClose: onClose)
          .padding(.leading, 22)
        Spacer()
        iconPill
          .padding(.trailing, 9)
      }
      .opacity(isKey ? 1 : 0)
    }
    .frame(height: EditorMetrics.topBarHeight)
  }

  private var iconPill: some View {
    HStack(spacing: 17) {
      pillButton(help: "Keyboard shortcuts", action: onShowShortcuts) {
        Image(nsImage: Self.commandIcon)
          .renderingMode(.template)
          .resizable()
          .frame(width: 16, height: 16)
      }
      .popover(isPresented: $shortcutsShown, arrowEdge: .bottom) {
        RaycastShortcutsPopover(theme: theme)
      }
      pillButton(help: "Switch note", action: onToggleNotes) {
        RaycastStackedCardsIcon()
      }
      pillButton(help: "New note", action: onNewNote) {
        Image(nsImage: Self.plusIcon)
          .renderingMode(.template)
          .resizable()
          .frame(width: 16, height: 16)
      }
    }
    .foregroundStyle(theme.text)
    .padding(.horizontal, 15)
    .frame(height: 30)
    .background(
      Capsule(style: .continuous)
        .fill(Color.white.opacity(0.03))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    )
  }

  private func pillButton(
    help: String,
    action: @escaping () -> Void,
    @ViewBuilder label: () -> some View
  ) -> some View {
    Button(action: action) {
      label()
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}

/// Raycast Notes-style bottom bar: centered live character counter and a
/// trailing circled "T" theme picker (hidden when the panel is not key).
struct RaycastBottomBar: View {
  let characterCount: Int
  let theme: Theme
  let isKey: Bool
  @ObservedObject var preferences: ThemePreferences
  @Binding var themePickerShown: Bool

  var body: some View {
    ZStack {
      Text(counterText)
        .font(.system(size: 16))
        .foregroundStyle(RaycastChromePalette.counter)
      HStack {
        Spacer()
        themeButton
      }
      .padding(.trailing, 14)
      .opacity(isKey ? 1 : 0)
    }
    .frame(height: EditorMetrics.bottomBarHeight)
  }

  private var counterText: String {
    characterCount == 1 ? "1 character" : "\(characterCount) characters"
  }

  private var themeButton: some View {
    Button {
      themePickerShown.toggle()
    } label: {
      Text("T")
        .font(.system(size: 14, weight: .medium, design: .serif))
        .foregroundStyle(RaycastChromePalette.control)
        .frame(width: 28, height: 28)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help("Theme")
    .popover(isPresented: $themePickerShown, arrowEdge: .top) {
      RaycastThemePopover(preferences: preferences)
    }
  }
}

/// Compact theme list shown from the bottom bar's "T" button.
struct RaycastThemePopover: View {
  @ObservedObject var preferences: ThemePreferences

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(ThemeCatalog.all) { theme in
          Button {
            preferences.selectedThemeID = theme.id
          } label: {
            HStack {
              Circle()
                .fill(theme.background)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                .frame(width: 12, height: 12)
              Text(theme.name)
              Spacer()
              if preferences.selectedThemeID == theme.id {
                Image(systemName: "checkmark")
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(.vertical, 3)
          .padding(.horizontal, 6)
        }
      }
      .padding(8)
    }
    .frame(width: 220, height: 280)
  }
}

/// Static shortcut reference shown from the title bar's command button,
/// backed by the same catalog as the Settings vim pane.
struct RaycastShortcutsPopover: View {
  let theme: Theme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(VimCommandReference.sections) { section in
          VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
            ForEach(section.entries) { entry in
              HStack(alignment: .top) {
                Text(entry.usage)
                  .font(.system(size: 11, design: .monospaced))
                  .frame(width: 130, alignment: .leading)
                Text(entry.summary)
                  .font(.system(size: 11))
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .padding(12)
    }
    .frame(width: 380, height: 320)
  }
}
