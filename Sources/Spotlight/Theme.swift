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
  let headingText: Color
  let placeholder: Color
  /// Block/insertion cursor color. `nil` falls back to the heading accent so a
  /// theme's cursor tracks its own palette instead of one global color; set it
  /// explicitly to honor a theme's official cursor (e.g. Fahrenheit's #bbbbbb).
  let cursor: Color?

  // #lizard forgives -- a plain field-assignment initializer; wide only because
  // Theme has many color roles. The `cursor` default keeps every existing theme
  // literal unchanged.
  init(
    id: String,
    name: String,
    mode: Mode,
    background: Color,
    border: Color,
    text: Color,
    headingText: Color,
    placeholder: Color,
    cursor: Color? = nil
  ) {
    self.id = id
    self.name = name
    self.mode = mode
    self.background = background
    self.border = border
    self.text = text
    self.headingText = headingText
    self.placeholder = placeholder
    self.cursor = cursor
  }

  /// Resolved cursor color: the explicit `cursor` when set, else the heading accent.
  var resolvedCursor: Color { cursor ?? headingText }
}

/// Curated themes: the original neutral set plus David's custom Catppuccin/Rose Pine/Ayu skins.
enum ThemeCatalog {
  // MARK: Dark

  /// Fahrenheit -- the cmuxthemes.com "dark warm orange" palette. Official spec:
  /// foreground #ffffce, background #000000, cursor #bbbbbb. The heading accent
  /// uses the palette's bright orange (ANSI 11, #fd9f4d).
  static let fahrenheit = Theme(
    id: "fahrenheit",
    name: "Fahrenheit",
    mode: .dark,
    background: Color(red: 0, green: 0, blue: 0),
    border: Color(red: 253 / 255, green: 159 / 255, blue: 77 / 255).opacity(0.24),
    text: Color(red: 255 / 255, green: 255 / 255, blue: 206 / 255),
    headingText: Color(red: 253 / 255, green: 159 / 255, blue: 77 / 255),
    placeholder: Color(red: 107 / 255, green: 102 / 255, blue: 80 / 255),
    cursor: Color(red: 187 / 255, green: 187 / 255, blue: 187 / 255)
  )

  static let catppuccinFrappe = Theme(
    id: "catppuccin-frappe",
    name: "Catppuccin Frappe",
    mode: .dark,
    background: Color(red: 0.188, green: 0.204, blue: 0.275),
    border: Color(red: 0.792, green: 0.651, blue: 0.957).opacity(0.24),
    text: Color(red: 0.776, green: 0.816, blue: 0.961),
    headingText: Color(red: 202 / 255, green: 158 / 255, blue: 230 / 255),
    placeholder: Color(red: 0.514, green: 0.545, blue: 0.655),
    cursor: Color(red: 242 / 255, green: 213 / 255, blue: 207 / 255)  // Rosewater
  )

  static let catppuccinMocha = Theme(
    id: "catppuccin-mocha",
    name: "Catppuccin Mocha",
    mode: .dark,
    background: Color(red: 0.118, green: 0.118, blue: 0.180),
    border: Color(red: 0.690, green: 0.611, blue: 0.914).opacity(0.24),
    text: Color(red: 0.804, green: 0.839, blue: 0.957),
    headingText: Color(red: 203 / 255, green: 166 / 255, blue: 247 / 255),
    placeholder: Color(red: 0.498, green: 0.518, blue: 0.612),
    cursor: Color(red: 245 / 255, green: 224 / 255, blue: 220 / 255)  // Rosewater
  )

  static let rosePineMoonlight = Theme(
    id: "rose-pine-moonlight",
    name: "Rose Pine Moonlight",
    mode: .dark,
    background: Color(red: 0.137, green: 0.129, blue: 0.212),
    border: Color(red: 0.769, green: 0.678, blue: 0.859).opacity(0.22),
    text: Color(red: 0.878, green: 0.871, blue: 0.957),
    headingText: Color(red: 196 / 255, green: 167 / 255, blue: 231 / 255),
    placeholder: Color(red: 0.431, green: 0.416, blue: 0.525),
    cursor: Color(red: 86 / 255, green: 82 / 255, blue: 110 / 255)  // Highlight High
  )

  static let ayuMirage = Theme(
    id: "ayu-mirage",
    name: "Ayu Mirage",
    mode: .dark,
    background: Color(red: 31 / 255, green: 36 / 255, blue: 48 / 255),
    border: Color(red: 255 / 255, green: 204 / 255, blue: 102 / 255).opacity(0.22),
    text: Color(red: 204 / 255, green: 202 / 255, blue: 194 / 255),
    headingText: Color(red: 255 / 255, green: 204 / 255, blue: 102 / 255),
    placeholder: Color(red: 104 / 255, green: 104 / 255, blue: 104 / 255)
  )

  static let mirage = Theme(
    id: "mirage",
    name: "Mirage",
    mode: .dark,
    background: Color(red: 27 / 255, green: 39 / 255, blue: 56 / 255),
    border: Color(red: 221 / 255, green: 179 / 255, blue: 255 / 255).opacity(0.22),
    text: Color(red: 166 / 255, green: 178 / 255, blue: 192 / 255),
    headingText: Color(red: 221 / 255, green: 179 / 255, blue: 255 / 255),
    placeholder: Color(red: 87 / 255, green: 86 / 255, blue: 86 / 255)
  )

  static let dracula = Theme(
    id: "dracula",
    name: "Dracula",
    mode: .dark,
    background: Color(red: 40 / 255, green: 42 / 255, blue: 54 / 255),
    border: Color(red: 255 / 255, green: 121 / 255, blue: 198 / 255).opacity(0.24),  // Pink
    text: Color(red: 248 / 255, green: 248 / 255, blue: 242 / 255),
    headingText: Color(red: 255 / 255, green: 121 / 255, blue: 198 / 255),  // Pink (Dracula accent)
    placeholder: Color(red: 98 / 255, green: 114 / 255, blue: 164 / 255),
    cursor: Color(red: 248 / 255, green: 248 / 255, blue: 242 / 255)  // Foreground
  )

  static let nvimDark = Theme(
    id: "nvim-dark",
    name: "Nvim Dark",
    mode: .dark,
    background: Color(red: 20 / 255, green: 22 / 255, blue: 27 / 255),
    border: Color(red: 155 / 255, green: 158 / 255, blue: 164 / 255).opacity(0.22),
    text: Color(red: 224 / 255, green: 226 / 255, blue: 234 / 255),
    headingText: Color(red: 166 / 255, green: 219 / 255, blue: 255 / 255),
    placeholder: Color(red: 79 / 255, green: 82 / 255, blue: 88 / 255),
    cursor: Color(red: 224 / 255, green: 226 / 255, blue: 234 / 255)  // Foreground
  )

  static let neobonesDark = Theme(
    id: "neobones-dark",
    name: "Neobones Dark",
    mode: .dark,
    background: Color(red: 15 / 255, green: 25 / 255, blue: 31 / 255),
    border: Color(red: 206 / 255, green: 221 / 255, blue: 215 / 255).opacity(0.20),
    text: Color(red: 198 / 255, green: 213 / 255, blue: 207 / 255),
    headingText: Color(red: 146 / 255, green: 160 / 255, blue: 226 / 255),
    placeholder: Color(red: 51 / 255, green: 70 / 255, blue: 82 / 255),
    cursor: Color(red: 206 / 255, green: 221 / 255, blue: 215 / 255)  // Near-foreground
  )

  static let nightfox = Theme(
    id: "nightfox",
    name: "Nightfox",
    mode: .dark,
    background: Color(red: 25 / 255, green: 35 / 255, blue: 48 / 255),
    border: Color(red: 205 / 255, green: 206 / 255, blue: 207 / 255).opacity(0.20),
    text: Color(red: 205 / 255, green: 206 / 255, blue: 207 / 255),
    headingText: Color(red: 113 / 255, green: 156 / 255, blue: 214 / 255),
    placeholder: Color(red: 87 / 255, green: 88 / 255, blue: 96 / 255),
    cursor: Color(red: 205 / 255, green: 206 / 255, blue: 207 / 255)  // Foreground
  )

  static let obsidian = Theme(
    id: "obsidian",
    name: "Obsidian",
    mode: .dark,
    background: Color(red: 0.055, green: 0.055, blue: 0.065),
    border: Color.white.opacity(0.06),
    text: Color(red: 0.910, green: 0.910, blue: 0.929),
    headingText: Color(red: 215 / 255, green: 201 / 255, blue: 255 / 255),
    placeholder: Color(red: 0.604, green: 0.604, blue: 0.627)
  )

  static let ink = Theme(
    id: "ink",
    name: "Ink",
    mode: .dark,
    background: Color(red: 0.071, green: 0.078, blue: 0.102),
    border: Color(red: 0.290, green: 0.333, blue: 0.408).opacity(0.25),
    text: Color(red: 0.886, green: 0.910, blue: 0.941),
    headingText: Color(red: 147 / 255, green: 197 / 255, blue: 253 / 255),
    placeholder: Color(red: 0.443, green: 0.502, blue: 0.588)
  )

  static let graphite = Theme(
    id: "graphite",
    name: "Graphite",
    mode: .dark,
    background: Color(red: 0.102, green: 0.102, blue: 0.102),
    border: Color.white.opacity(0.10),
    text: Color(red: 0.831, green: 0.831, blue: 0.831),
    headingText: Color(red: 229 / 255, green: 231 / 255, blue: 235 / 255),
    placeholder: Color(red: 0.502, green: 0.502, blue: 0.502)
  )

  static let midnight = Theme(
    id: "midnight",
    name: "Midnight",
    mode: .dark,
    background: Color(red: 0.059, green: 0.078, blue: 0.098),
    border: Color(red: 0.118, green: 0.165, blue: 0.220).opacity(0.80),
    text: Color(red: 0.839, green: 0.871, blue: 0.922),
    headingText: Color(red: 125 / 255, green: 211 / 255, blue: 252 / 255),
    placeholder: Color(red: 0.373, green: 0.494, blue: 0.592)
  )

  static let charcoal = Theme(
    id: "charcoal",
    name: "Charcoal",
    mode: .dark,
    background: Color(red: 0.110, green: 0.110, blue: 0.118),
    border: Color.white.opacity(0.08),
    text: Color(red: 0.922, green: 0.922, blue: 0.941),
    headingText: Color(red: 196 / 255, green: 181 / 255, blue: 253 / 255),
    placeholder: Color(red: 0.557, green: 0.557, blue: 0.576)
  )

  // MARK: Light

  static let catppuccinLatte = Theme(
    id: "catppuccin-latte",
    name: "Catppuccin Latte",
    mode: .light,
    background: Color(red: 0.937, green: 0.945, blue: 0.961),
    border: Color(red: 0.533, green: 0.224, blue: 0.765).opacity(0.16),
    text: Color(red: 0.298, green: 0.310, blue: 0.412),
    headingText: Color(red: 136 / 255, green: 57 / 255, blue: 239 / 255),  // Mauve (official Latte accent)
    placeholder: Color(red: 0.549, green: 0.561, blue: 0.631),
    cursor: Color(red: 220 / 255, green: 138 / 255, blue: 120 / 255)  // Rosewater
  )

  static let parchment = Theme(
    id: "parchment",
    name: "Parchment",
    mode: .light,
    background: Color(red: 0.969, green: 0.961, blue: 0.937),
    border: Color.black.opacity(0.08),
    text: Color(red: 0.165, green: 0.165, blue: 0.165),
    headingText: Color(red: 87 / 255, green: 56 / 255, blue: 138 / 255),
    placeholder: Color(red: 0.557, green: 0.541, blue: 0.510)
  )

  static let mist = Theme(
    id: "mist",
    name: "Mist",
    mode: .light,
    background: Color(red: 0.965, green: 0.969, blue: 0.976),
    border: Color.black.opacity(0.06),
    text: Color(red: 0.122, green: 0.161, blue: 0.216),
    headingText: Color(red: 87 / 255, green: 56 / 255, blue: 138 / 255),
    placeholder: Color(red: 0.612, green: 0.639, blue: 0.686)
  )

  static let bone = Theme(
    id: "bone",
    name: "Bone",
    mode: .light,
    background: Color(red: 0.980, green: 0.980, blue: 0.973),
    border: Color.black.opacity(0.05),
    text: Color(red: 0.149, green: 0.149, blue: 0.149),
    headingText: Color(red: 87 / 255, green: 56 / 255, blue: 138 / 255),
    placeholder: Color(red: 0.549, green: 0.549, blue: 0.549)
  )

  static let linen = Theme(
    id: "linen",
    name: "Linen",
    mode: .light,
    background: Color(red: 0.961, green: 0.941, blue: 0.910),
    border: Color.black.opacity(0.07),
    text: Color(red: 0.239, green: 0.184, blue: 0.122),
    headingText: Color(red: 87 / 255, green: 56 / 255, blue: 138 / 255),
    placeholder: Color(red: 0.612, green: 0.557, blue: 0.478)
  )

  static let porcelain = Theme(
    id: "porcelain",
    name: "Porcelain",
    mode: .light,
    background: Color.white,
    border: Color.black.opacity(0.07),
    text: Color(red: 0.102, green: 0.102, blue: 0.102),
    headingText: Color(red: 87 / 255, green: 56 / 255, blue: 138 / 255),
    placeholder: Color(red: 0.557, green: 0.557, blue: 0.576)
  )

  static let darkThemes: [Theme] = [
    fahrenheit, catppuccinFrappe, catppuccinMocha, rosePineMoonlight, ayuMirage, mirage, dracula,
    nvimDark, neobonesDark, nightfox, obsidian, ink, graphite, midnight, charcoal
  ]
  static let lightThemes: [Theme] = [catppuccinLatte, parchment, mist, bone, linen, porcelain]
  static let all: [Theme] = darkThemes + lightThemes

  /// Default theme applied on first launch.
  static let defaultID = mirage.id

  /// Looks up a theme by id, falling back to the default.
  static func theme(withID id: String) -> Theme {
    all.first { $0.id == id } ?? mirage
  }
}
