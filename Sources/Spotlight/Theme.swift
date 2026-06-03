import SwiftUI

/// Visual skin applied to the HUD panel.
public struct Theme: Equatable, Identifiable, Sendable {
  public enum Mode: String, Codable, Sendable { case light, dark }

  public let id: String
  let name: String
  let mode: Mode
  let background: Color
  let border: Color
  let text: Color
  let placeholder: Color
  let statusLine: ThemeStatusLine

  var cursor: Color {
    switch id {
    case ThemeCatalog.catppuccinLatte.id: Color(red: 1.000, green: 0.392, blue: 0.043)
    case ThemeCatalog.catppuccinFrappe.id: Color(red: 0.937, green: 0.624, blue: 0.463)
    case ThemeCatalog.catppuccinMocha.id: Color(red: 0.980, green: 0.702, blue: 0.529)
    case ThemeCatalog.rosePineDawn.id: Color(red: 0.843, green: 0.510, blue: 0.494)
    case ThemeCatalog.rosePineMoonlight.id: Color(red: 0.918, green: 0.604, blue: 0.592)
    default: Self.defaultCursor(for: mode)
    }
  }

  var flash: ThemeFlashPalette {
    ThemeFlashPalette.palette(for: self)
  }

  private static func defaultCursor(for mode: Mode) -> Color {
    mode == .dark
      ? Color(red: 0.973, green: 0.973, blue: 0.941)
      : Color(red: 0.165, green: 0.165, blue: 0.165)
  }
}

/// Status-line palette tokens, mirroring Neovim theme highlight groups.
struct ThemeStatusLine: Equatable, Sendable {
  let fileFill: Color
  let trailingFill: Color
  let fileText: Color
  let trailingText: Color
  let normalFill: Color
  let normalText: Color
  let insertFill: Color
  let insertText: Color
  let visualLineFill: Color
  let visualLineText: Color

  func modeFill(for mode: VimMode) -> Color {
    switch mode {
    case .normal: return normalFill
    case .insert: return insertFill
    case .visualLine: return visualLineFill
    }
  }

  func modeText(for mode: VimMode) -> Color {
    switch mode {
    case .normal: return normalText
    case .insert: return insertText
    case .visualLine: return visualLineText
    }
  }

  static let rosePineMoon = ThemeStatusLine(
    fileFill: Color(red: 0.224, green: 0.208, blue: 0.322),
    trailingFill: Color(red: 0.165, green: 0.153, blue: 0.247),
    fileText: Color(red: 0.878, green: 0.871, blue: 0.957),
    trailingText: Color(red: 0.565, green: 0.549, blue: 0.667),
    normalFill: Color(red: 0.612, green: 0.812, blue: 0.847),
    normalText: Color(red: 0.137, green: 0.129, blue: 0.212),
    insertFill: Color(red: 0.243, green: 0.561, blue: 0.690),
    insertText: Color(red: 0.137, green: 0.129, blue: 0.212),
    visualLineFill: Color(red: 0.769, green: 0.655, blue: 0.906),
    visualLineText: Color(red: 0.137, green: 0.129, blue: 0.212)
  )

  static let rosePineDawn = ThemeStatusLine(
    fileFill: Color(red: 0.949, green: 0.914, blue: 0.882),
    trailingFill: Color(red: 1.000, green: 0.980, blue: 0.953),
    fileText: Color(red: 0.275, green: 0.259, blue: 0.380),
    trailingText: Color(red: 0.475, green: 0.459, blue: 0.576),
    normalFill: Color(red: 0.337, green: 0.580, blue: 0.624),
    normalText: Color(red: 0.980, green: 0.957, blue: 0.929),
    insertFill: Color(red: 0.157, green: 0.412, blue: 0.514),
    insertText: Color(red: 0.980, green: 0.957, blue: 0.929),
    visualLineFill: Color(red: 0.565, green: 0.478, blue: 0.663),
    visualLineText: Color(red: 0.980, green: 0.957, blue: 0.929)
  )

  static let catppuccinLatte = ThemeStatusLine(
    fileFill: Color(red: 0.863, green: 0.878, blue: 0.910),
    trailingFill: Color(red: 0.902, green: 0.914, blue: 0.937),
    fileText: Color(red: 0.298, green: 0.310, blue: 0.412),
    trailingText: Color(red: 0.361, green: 0.373, blue: 0.467),
    normalFill: Color(red: 0.118, green: 0.400, blue: 0.961),
    normalText: Color(red: 0.937, green: 0.945, blue: 0.961),
    insertFill: Color(red: 0.251, green: 0.627, blue: 0.169),
    insertText: Color(red: 0.937, green: 0.945, blue: 0.961),
    visualLineFill: Color(red: 0.533, green: 0.224, blue: 0.937),
    visualLineText: Color(red: 0.937, green: 0.945, blue: 0.961)
  )

  static let catppuccinFrappe = ThemeStatusLine(
    fileFill: Color(red: 0.137, green: 0.149, blue: 0.204),
    trailingFill: Color(red: 0.161, green: 0.173, blue: 0.235),
    fileText: Color(red: 0.776, green: 0.816, blue: 0.961),
    trailingText: Color(red: 0.710, green: 0.749, blue: 0.886),
    normalFill: Color(red: 0.549, green: 0.667, blue: 0.933),
    normalText: Color(red: 0.188, green: 0.204, blue: 0.275),
    insertFill: Color(red: 0.651, green: 0.820, blue: 0.537),
    insertText: Color(red: 0.188, green: 0.204, blue: 0.275),
    visualLineFill: Color(red: 0.792, green: 0.620, blue: 0.902),
    visualLineText: Color(red: 0.188, green: 0.204, blue: 0.275)
  )

  static let catppuccinMocha = ThemeStatusLine(
    fileFill: Color(red: 0.067, green: 0.067, blue: 0.106),
    trailingFill: Color(red: 0.094, green: 0.094, blue: 0.145),
    fileText: Color(red: 0.804, green: 0.839, blue: 0.957),
    trailingText: Color(red: 0.729, green: 0.761, blue: 0.871),
    normalFill: Color(red: 0.537, green: 0.706, blue: 0.980),
    normalText: Color(red: 0.118, green: 0.118, blue: 0.180),
    insertFill: Color(red: 0.651, green: 0.890, blue: 0.631),
    insertText: Color(red: 0.118, green: 0.118, blue: 0.180),
    visualLineFill: Color(red: 0.796, green: 0.651, blue: 0.969),
    visualLineText: Color(red: 0.118, green: 0.118, blue: 0.180)
  )

  static func fallback(for mode: Theme.Mode, text: Color) -> ThemeStatusLine {
    ThemeStatusLine(
      fileFill: mode == .dark ? Color(red: 0.26, green: 0.28, blue: 0.38).opacity(0.90) : Color.black.opacity(0.10),
      trailingFill: mode == .dark ? Color(red: 0.33, green: 0.36, blue: 0.47).opacity(0.88) : Color.black.opacity(0.07),
      fileText: text.opacity(0.94),
      trailingText: text.opacity(0.58),
      normalFill: Color(red: 0.55, green: 0.69, blue: 0.98),
      normalText: Color(red: 0.07, green: 0.10, blue: 0.18),
      insertFill: Color(red: 0.65, green: 0.89, blue: 0.63),
      insertText: Color(red: 0.06, green: 0.13, blue: 0.08),
      visualLineFill: Color(red: 0.80, green: 0.67, blue: 0.94),
      visualLineText: Color(red: 0.13, green: 0.08, blue: 0.18)
    )
  }
}

/// Flash jump palette tokens, based on folke/flash.nvim highlight groups.
struct ThemeFlashPalette: Equatable, Sendable {
  let backdropText: Color
  let matchText: Color
  let labelText: Color
  let labelFill: Color
  let activeLabelText: Color
  let activeLabelFill: Color

  static let catppuccinLatte = ThemeFlashPalette(
    backdropText: Color(red: 0.612, green: 0.627, blue: 0.690),
    matchText: Color(red: 0.447, green: 0.529, blue: 0.992),
    labelText: Color(red: 0.937, green: 0.945, blue: 0.961),
    labelFill: Color(red: 0.251, green: 0.627, blue: 0.169),
    activeLabelText: Color(red: 0.937, green: 0.945, blue: 0.961),
    activeLabelFill: Color(red: 1.000, green: 0.392, blue: 0.043)
  )

  static let catppuccinFrappe = ThemeFlashPalette(
    backdropText: Color(red: 0.451, green: 0.475, blue: 0.580),
    matchText: Color(red: 0.729, green: 0.733, blue: 0.945),
    labelText: Color(red: 0.188, green: 0.204, blue: 0.275),
    labelFill: Color(red: 0.651, green: 0.820, blue: 0.537),
    activeLabelText: Color(red: 0.188, green: 0.204, blue: 0.275),
    activeLabelFill: Color(red: 0.937, green: 0.624, blue: 0.463)
  )

  static let catppuccinMocha = ThemeFlashPalette(
    backdropText: Color(red: 0.424, green: 0.439, blue: 0.525),
    matchText: Color(red: 0.706, green: 0.745, blue: 0.996),
    labelText: Color(red: 0.118, green: 0.118, blue: 0.180),
    labelFill: Color(red: 0.651, green: 0.890, blue: 0.631),
    activeLabelText: Color(red: 0.118, green: 0.118, blue: 0.180),
    activeLabelFill: Color(red: 0.980, green: 0.702, blue: 0.529)
  )

  static let rosePineDawn = ThemeFlashPalette(
    backdropText: Color(red: 0.596, green: 0.576, blue: 0.647),
    matchText: Color(red: 0.565, green: 0.478, blue: 0.663),
    labelText: Color(red: 0.980, green: 0.957, blue: 0.929),
    labelFill: Color(red: 0.706, green: 0.388, blue: 0.478),
    activeLabelText: Color(red: 0.980, green: 0.957, blue: 0.929),
    activeLabelFill: Color(red: 0.918, green: 0.616, blue: 0.204)
  )

  static let rosePineMoon = ThemeFlashPalette(
    backdropText: Color(red: 0.431, green: 0.408, blue: 0.506),
    matchText: Color(red: 0.769, green: 0.655, blue: 0.906),
    labelText: Color(red: 0.137, green: 0.129, blue: 0.212),
    labelFill: Color(red: 0.922, green: 0.435, blue: 0.573),
    activeLabelText: Color(red: 0.137, green: 0.129, blue: 0.212),
    activeLabelFill: Color(red: 0.965, green: 0.757, blue: 0.467)
  )

  static func palette(for theme: Theme) -> ThemeFlashPalette {
    switch theme.id {
    case ThemeCatalog.catppuccinLatte.id: .catppuccinLatte
    case ThemeCatalog.catppuccinFrappe.id: .catppuccinFrappe
    case ThemeCatalog.catppuccinMocha.id: .catppuccinMocha
    case ThemeCatalog.rosePineDawn.id: .rosePineDawn
    case ThemeCatalog.rosePineMoonlight.id: .rosePineMoon
    default:
      .fallback(
        for: theme.mode,
        text: theme.text,
        placeholder: theme.placeholder,
        background: theme.background
      )
    }
  }

  static func fallback(
    for mode: Theme.Mode,
    text: Color,
    placeholder: Color,
    background: Color
  ) -> ThemeFlashPalette {
    ThemeFlashPalette(
      backdropText: placeholder,
      matchText: mode == .dark ? Color(red: 0.804, green: 0.839, blue: 1.000) : text,
      labelText: background,
      labelFill: mode == .dark
        ? Color(red: 0.651, green: 0.890, blue: 0.631) : Color(red: 0.251, green: 0.627, blue: 0.169),
      activeLabelText: background,
      activeLabelFill: mode == .dark
        ? Color(red: 0.980, green: 0.702, blue: 0.529) : Color(red: 1.000, green: 0.392, blue: 0.043)
    )
  }
}

/// Fifteen curated themes -- eight dark, seven light.
enum ThemeCatalog {
  // MARK: Dark

  static let obsidian = Theme(
    id: "obsidian",
    name: "Obsidian",
    mode: .dark,
    background: Color(red: 0.055, green: 0.055, blue: 0.065),
    border: Color.white.opacity(0.06),
    text: Color(red: 0.910, green: 0.910, blue: 0.929),
    placeholder: Color(red: 0.604, green: 0.604, blue: 0.627),
    statusLine: .fallback(for: .dark, text: Color(red: 0.910, green: 0.910, blue: 0.929))
  )

  static let ink = Theme(
    id: "ink",
    name: "Ink",
    mode: .dark,
    background: Color(red: 0.071, green: 0.078, blue: 0.102),
    border: Color(red: 0.290, green: 0.333, blue: 0.408).opacity(0.25),
    text: Color(red: 0.886, green: 0.910, blue: 0.941),
    placeholder: Color(red: 0.443, green: 0.502, blue: 0.588),
    statusLine: .fallback(for: .dark, text: Color(red: 0.886, green: 0.910, blue: 0.941))
  )

  static let graphite = Theme(
    id: "graphite",
    name: "Graphite",
    mode: .dark,
    background: Color(red: 0.102, green: 0.102, blue: 0.102),
    border: Color.white.opacity(0.10),
    text: Color(red: 0.831, green: 0.831, blue: 0.831),
    placeholder: Color(red: 0.502, green: 0.502, blue: 0.502),
    statusLine: .fallback(for: .dark, text: Color(red: 0.831, green: 0.831, blue: 0.831))
  )

  static let midnight = Theme(
    id: "midnight",
    name: "Midnight",
    mode: .dark,
    background: Color(red: 0.059, green: 0.078, blue: 0.098),
    border: Color(red: 0.118, green: 0.165, blue: 0.220).opacity(0.80),
    text: Color(red: 0.839, green: 0.871, blue: 0.922),
    placeholder: Color(red: 0.373, green: 0.494, blue: 0.592),
    statusLine: .fallback(for: .dark, text: Color(red: 0.839, green: 0.871, blue: 0.922))
  )

  static let charcoal = Theme(
    id: "charcoal",
    name: "Charcoal",
    mode: .dark,
    background: Color(red: 0.110, green: 0.110, blue: 0.118),
    border: Color.white.opacity(0.08),
    text: Color(red: 0.922, green: 0.922, blue: 0.941),
    placeholder: Color(red: 0.557, green: 0.557, blue: 0.576),
    statusLine: .fallback(for: .dark, text: Color(red: 0.922, green: 0.922, blue: 0.941))
  )

  static let rosePineMoonlight = Theme(
    id: "rose-pine-moonlight",
    name: "Rosé Pine Moonlight",
    mode: .dark,
    background: Color(red: 0.137, green: 0.129, blue: 0.212),
    border: Color(red: 0.267, green: 0.255, blue: 0.353),
    text: Color(red: 0.878, green: 0.839, blue: 0.808),
    placeholder: Color(red: 0.431, green: 0.408, blue: 0.506),
    statusLine: .rosePineMoon
  )

  static let catppuccinFrappe = Theme(
    id: "catppuccin-frappe",
    name: "Catppuccin Frappé",
    mode: .dark,
    background: Color(red: 0.188, green: 0.204, blue: 0.275),
    border: Color(red: 0.255, green: 0.271, blue: 0.349),
    text: Color(red: 0.776, green: 0.816, blue: 0.961),
    placeholder: Color(red: 0.451, green: 0.475, blue: 0.580),
    statusLine: .catppuccinFrappe
  )

  static let catppuccinMocha = Theme(
    id: "catppuccin-mocha",
    name: "Catppuccin Mocha",
    mode: .dark,
    background: Color(red: 0.118, green: 0.118, blue: 0.180),
    border: Color(red: 0.192, green: 0.196, blue: 0.267),
    text: Color(red: 0.804, green: 0.839, blue: 0.957),
    placeholder: Color(red: 0.424, green: 0.439, blue: 0.525),
    statusLine: .catppuccinMocha
  )

  // MARK: Light

  static let rosePineDawn = Theme(
    id: "rose-pine-dawn",
    name: "Rosé Pine Dawn",
    mode: .light,
    background: Color(red: 0.980, green: 0.957, blue: 0.929),
    border: Color(red: 0.875, green: 0.855, blue: 0.851),
    text: Color(red: 0.275, green: 0.259, blue: 0.380),
    placeholder: Color(red: 0.596, green: 0.576, blue: 0.647),
    statusLine: .rosePineDawn
  )

  static let catppuccinLatte = Theme(
    id: "catppuccin-latte",
    name: "Catppuccin Latte",
    mode: .light,
    background: Color(red: 0.937, green: 0.945, blue: 0.961),
    border: Color(red: 0.800, green: 0.816, blue: 0.855),
    text: Color(red: 0.298, green: 0.310, blue: 0.412),
    placeholder: Color(red: 0.612, green: 0.627, blue: 0.690),
    statusLine: .catppuccinLatte
  )

  static let parchment = Theme(
    id: "parchment",
    name: "Parchment",
    mode: .light,
    background: Color(red: 0.969, green: 0.961, blue: 0.937),
    border: Color.black.opacity(0.08),
    text: Color(red: 0.165, green: 0.165, blue: 0.165),
    placeholder: Color(red: 0.557, green: 0.541, blue: 0.510),
    statusLine: .fallback(for: .light, text: Color(red: 0.165, green: 0.165, blue: 0.165))
  )

  static let mist = Theme(
    id: "mist",
    name: "Mist",
    mode: .light,
    background: Color(red: 0.965, green: 0.969, blue: 0.976),
    border: Color.black.opacity(0.06),
    text: Color(red: 0.122, green: 0.161, blue: 0.216),
    placeholder: Color(red: 0.612, green: 0.639, blue: 0.686),
    statusLine: .fallback(for: .light, text: Color(red: 0.122, green: 0.161, blue: 0.216))
  )

  static let bone = Theme(
    id: "bone",
    name: "Bone",
    mode: .light,
    background: Color(red: 0.980, green: 0.980, blue: 0.973),
    border: Color.black.opacity(0.05),
    text: Color(red: 0.149, green: 0.149, blue: 0.149),
    placeholder: Color(red: 0.549, green: 0.549, blue: 0.549),
    statusLine: .fallback(for: .light, text: Color(red: 0.149, green: 0.149, blue: 0.149))
  )

  static let linen = Theme(
    id: "linen",
    name: "Linen",
    mode: .light,
    background: Color(red: 0.961, green: 0.941, blue: 0.910),
    border: Color.black.opacity(0.07),
    text: Color(red: 0.239, green: 0.184, blue: 0.122),
    placeholder: Color(red: 0.612, green: 0.557, blue: 0.478),
    statusLine: .fallback(for: .light, text: Color(red: 0.239, green: 0.184, blue: 0.122))
  )

  static let porcelain = Theme(
    id: "porcelain",
    name: "Porcelain",
    mode: .light,
    background: Color.white,
    border: Color.black.opacity(0.07),
    text: Color(red: 0.102, green: 0.102, blue: 0.102),
    placeholder: Color(red: 0.557, green: 0.557, blue: 0.576),
    statusLine: .fallback(for: .light, text: Color(red: 0.102, green: 0.102, blue: 0.102))
  )

  static let darkThemes: [Theme] = [
    obsidian,
    ink,
    graphite,
    midnight,
    charcoal,
    rosePineMoonlight,
    catppuccinFrappe,
    catppuccinMocha
  ]
  static let lightThemes: [Theme] = [
    rosePineDawn,
    catppuccinLatte,
    parchment,
    mist,
    bone,
    linen,
    porcelain
  ]
  static let all: [Theme] = darkThemes + lightThemes

  /// Default theme applied on first launch.
  static let defaultID = rosePineMoonlight.id

  /// Looks up a theme by id, falling back to the default.
  static func theme(withID id: String) -> Theme {
    all.first { $0.id == id } ?? rosePineMoonlight
  }
}
