import Foundation

enum SpotNoteSectionHeadings {
  static let bigThings = Definition(canonical: "## Big Things", aliases: [])
  static let habits = Definition(canonical: "## Habits", aliases: [])
  static let todo = Definition(canonical: "## Todo", aliases: ["## To Do"])
  static let tray = Definition(canonical: "## Tray", aliases: [])

  /// All sections, ordered so that overlapping spellings resolve correctly when
  /// normalizing a heading line: a non-leading `## TODO` is a Todo section, not
  /// the Habits legacy alias. (Matching is case- and heading-level-insensitive.)
  static let all: [Definition] = [bigThings, todo, tray, habits]

  /// The canonical (Title-Case) form of `line` if it names a known section,
  /// else nil. Used to normalize a note's headings to a consistent spelling.
  static func canonicalHeading(for line: String) -> String? {
    all.first { $0.matches(line) }?.canonical
  }

  struct Definition {
    let canonical: String
    let aliases: [String]

    var allSpellings: [String] { [canonical] + aliases }

    /// Matches a heading line by section name, ignoring the heading level the
    /// user typed -- `# TODO`, `## TODO`, and `### TODO` all match the TODO
    /// section. Non-heading lines never match.
    func matches(_ line: String) -> Bool {
      guard let name = Self.sectionName(from: line) else { return false }
      return allSpellings.contains { Self.sectionName(from: $0) == name }
    }

    /// Lowercased section name of a `#`-prefixed heading (e.g. "# TODO" and
    /// "## TODO" both yield "todo"); nil when the line is not a heading.
    private static func sectionName(from line: String) -> String? {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("#") else { return nil }
      return trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var canonicalLine: String { canonical + "\n" }
  }
}
