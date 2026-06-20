import Foundation

enum SpotNoteSectionHeadings {
  static let habits = Definition(canonical: "## HABITS", aliases: ["## TODO", "## To Do"])
  static let todo = Definition(canonical: "## TODO", aliases: ["## To Do"])
  static let tray = Definition(canonical: "## TRAY", aliases: ["## Tray"])

  struct Definition {
    let canonical: String
    let aliases: [String]

    var allSpellings: [String] { [canonical] + aliases }

    func matches(_ line: String) -> Bool {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      return allSpellings.contains {
        trimmed.localizedCaseInsensitiveCompare($0) == .orderedSame
      }
    }

    var canonicalLine: String { canonical + "\n" }
  }
}
