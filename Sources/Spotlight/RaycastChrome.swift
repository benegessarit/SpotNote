import AppKit
import SwiftUI

/// Shared palette for the Raycast Notes shell chrome. These greys are part
/// of the shell identity (pixel-sampled from the live Raycast Beta Notes
/// window) and intentionally do not follow the editor theme.
enum RaycastChromePalette {
  /// Raycast authors its saturated colors in Display P3: the live close
  /// button reads (236,103,101) raw on the display, which an sRGB
  /// #EC6765 undershoots (renders ~(220,111,105)).
  static let closeRed = Color(.displayP3, red: 0xEC / 255, green: 0x67 / 255, blue: 0x65 / 255)
  static let inactiveDot = Color(red: 0x46 / 255, green: 0x48 / 255, blue: 0x56 / 255)
  static let titleKey = Color(red: 0x8C / 255, green: 0x90 / 255, blue: 0xA6 / 255)
  static let counter = Color(red: 0x48 / 255, green: 0x4C / 255, blue: 0x5B / 255)
  static let control = Color(red: 0x76 / 255, green: 0x7D / 255, blue: 0x91 / 255)
  /// Pill icon tint while the panel is resigned (probed (76,78,89) in the
  /// live resigned window -- the pill stays visible, only dimmed).
  static let controlResigned = Color(red: 0x4C / 255, green: 0x4E / 255, blue: 0x59 / 255)
  /// The icon pill's fill is a solid near-surface tone (#25262E probed),
  /// not a white wash -- it reads slightly warmer than the gradient.
  static let pillFill = Color(red: 0x25 / 255, green: 0x26 / 255, blue: 0x2E / 255)
}

/// Raycast Notes draws its own traffic lights: 14pt dots at 23pt centers,
/// close active red (with an x on hover), minimize/zoom rendered as
/// disabled grey dots. Only close is interactive. When the panel resigns
/// key, close joins the other two in grey -- the lights stay visible
/// (pixel-probed in the live resigned window).
struct RaycastTrafficLights: View {
  let isKey: Bool
  let onClose: () -> Void
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 9) {
      Button(action: onClose) {
        ZStack {
          Circle()
            .fill(isKey ? RaycastChromePalette.closeRed : RaycastChromePalette.inactiveDot)
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
/// public @raycast/icons set, so it is drawn directly. `scale` shrinks the
/// whole drawing uniformly (1 = the pill's 19.5pt visible size).
struct RaycastStackedCardsIcon: View {
  var scale: CGFloat = 1

  var body: some View {
    ZStack {
      card
        .stroke(style: strokeStyle)
        .frame(width: 12.2 * scale, height: 14.5 * scale)
        .rotationEffect(.degrees(-8))
        .offset(x: -2.2 * scale, y: 1.6 * scale)
      card
        .fill(Color.black)
        .frame(width: 12.2 * scale, height: 14.5 * scale)
        .rotationEffect(.degrees(12))
        .offset(x: 2.3 * scale, y: -1.6 * scale)
        .blendMode(.destinationOut)
      card
        .stroke(style: strokeStyle)
        .frame(width: 12.2 * scale, height: 14.5 * scale)
        .rotationEffect(.degrees(12))
        .offset(x: 2.3 * scale, y: -1.6 * scale)
    }
    .compositingGroup()
    .frame(width: 20 * scale, height: 20 * scale)
  }

  private var card: RoundedRectangle {
    RoundedRectangle(cornerRadius: 3.4 * scale, style: .continuous)
  }

  private var strokeStyle: StrokeStyle {
    StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round, lineJoin: .round)
  }
}

/// The pill's new-note plus, drawn instead of rasterized: the live glyph
/// is an 18pt cross stroked at 2pt with round caps (probed 36x36px @2x
/// with 4px stems); the bundled raster's stroke scales to 3pt at pill
/// size, which reads visibly heavier.
struct RaycastPlusShape: Shape {
  func path(in rect: CGRect) -> Path {
    // Inset by the 1pt cap radius so the ROUND CAPS land exactly on the
    // frame edge -- the visible cross fills the frame, no more.
    let inset = rect.insetBy(dx: 1, dy: 1)
    var path = Path()
    path.move(to: CGPoint(x: inset.midX, y: inset.minY))
    path.addLine(to: CGPoint(x: inset.midX, y: inset.maxY))
    path.move(to: CGPoint(x: inset.minX, y: inset.midY))
    path.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
    return path
  }
}

/// Loads a bundled Raycast icon rasterized from the exact @raycast/icons
/// path data, tinted at render time via template mode.
func raycastIconImage(_ resource: String) -> NSImage {
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
  let onShowActions: () -> Void
  let onToggleNotes: () -> Void
  let onNewNote: () -> Void

  /// Width reserved at the leading edge for the traffic lights.
  static let trafficLightGutter: CGFloat = 90

  private static let commandIcon = raycastIconImage("RaycastCommandSymbol")

  var body: some View {
    ZStack {
      Text(title)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(RaycastChromePalette.titleKey)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Self.trafficLightGutter + 30)
      HStack {
        RaycastTrafficLights(isKey: isKey, onClose: onClose)
          .padding(.leading, 23)
        Spacer()
        iconPill
          .padding(.trailing, 9)
      }
    }
    .frame(height: EditorMetrics.topBarHeight)
  }

  /// Every button sits in a uniform 30pt hover cell; the glyph frames
  /// inside differ (rasters carry internal padding, the drawn icons
  /// none) so each VISIBLE glyph matches the live app's uniform ~17.5pt.
  /// The gaps keep the visible glyph-to-glyph spacing at the probed
  /// 15.5pt despite the differing internal padding.
  private var iconPill: some View {
    HStack(spacing: 0) {
      PillIconButton(help: "Actions", action: onShowActions) {
        Image(nsImage: Self.commandIcon)
          .renderingMode(.template)
          .resizable()
          .frame(width: 20, height: 20)
      }
      Spacer().frame(width: 4)
      PillIconButton(help: "Browse notes", action: onToggleNotes) {
        RaycastStackedCardsIcon()
      }
      Spacer().frame(width: 4)
      PillIconButton(help: "New note", action: onNewNote) {
        RaycastPlusShape()
          .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .frame(width: 18, height: 18)
      }
    }
    .foregroundStyle(isKey ? theme.text : RaycastChromePalette.controlResigned)
    .padding(.leading, 7)
    .padding(.trailing, 6)
    .frame(height: 44)
    .background(
      Capsule(style: .continuous)
        .fill(RaycastChromePalette.pillFill)
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    )
  }
}

/// Pill icon button with the live app's hover reaction: a soft rounded
/// highlight fills the button's cell while the pointer is over it.
private struct PillIconButton<Label: View>: View {
  let help: String
  let action: () -> Void
  @ViewBuilder let label: () -> Label
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      label()
        .frame(width: 30, height: 30)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(hovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
    .onHover { hovering = $0 }
  }
}

/// Raycast Notes-style bottom bar: just the centered live character
/// counter. Theme switching lives in the actions modal, not here.
struct RaycastBottomBar: View {
  let characterCount: Int

  var body: some View {
    Text(counterText)
      .font(.system(size: 16))
      .foregroundStyle(RaycastChromePalette.counter)
      .frame(height: EditorMetrics.bottomBarHeight)
      .frame(maxWidth: .infinity)
  }

  private var counterText: String {
    characterCount == 1 ? "1 character" : "\(characterCount) characters"
  }
}
