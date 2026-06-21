import Foundation

enum SpotNoteSectionHeadings {
  static let habits = Definition(canonical: "## HABITS", aliases: ["## TODO", "## To Do"])
  static let todo = Definition(canonical: "## TODO", aliases: ["## To Do"])
  static let tray = Definition(canonical: "## TRAY", aliases: ["## Tray"])

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
