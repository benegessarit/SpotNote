import AppKit

extension LineNumberRuler {
  static func signColumnWidth(forLabelSize labelSize: CGFloat) -> CGFloat {
    let digitFont = NSFont.monospacedDigitSystemFont(ofSize: labelSize, weight: .regular)
    let digitWidth = ("8" as NSString).size(withAttributes: [.font: digitFont]).width
    return ceil(max(digitWidth, flashLabelColumnWidth(forLabelSize: labelSize))) + 4
  }

  static func markerOnlyThickness(forLabelSize _: CGFloat) -> CGFloat {
    0
  }

  private static func flashLabelColumnWidth(forLabelSize labelSize: CGFloat) -> CGFloat {
    let font = NSFont.boldSystemFont(ofSize: labelSize)
    let twoCharacterLabelWidth = ("aa" as NSString).size(withAttributes: [.font: font]).width
    return ceil(twoCharacterLabelWidth) + 2
  }
}
