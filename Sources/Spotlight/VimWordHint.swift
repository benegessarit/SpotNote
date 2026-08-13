import Foundation

/// Hop-style every-word hint jump: the moment `s` is pressed, every visible
/// word start gets a label and the first label keypress jumps -- no search
/// phase. Ported from hop.nvim as configured in David's nvim: the
/// TrieBacktrackFilling permutation generator (`hop/perm.lua`), Manhattan
/// distance scoring with `x_bias = 10` (`hop/defaults.lua` +
/// `hint.manh_distance`), and the touching-run alternate-color pass from the
/// local `set_hint_extmarks` wrapper in `lua/plugins/hop.lua`.
enum VimWordHint {
  /// hop.nvim's default label charset (`defaults.lua M.keys`).
  static let labelKeys: [Character] = Array("asdghklqwertyuiopzxcvbnmfj")

  /// Row/column of a UTF-16 offset, both zero-based. Columns are UTF-16
  /// units (hop uses byte columns; ordering and distance semantics match).
  struct Position: Equatable, Sendable {
    let row: Int
    let col: Int
  }

  // MARK: - Word-start scanning

  private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

  /// UTF-16 offsets of every word start inside `range`, in document order.
  /// A word start is a keyword character (letter, digit, underscore -- vim
  /// `\k`) whose predecessor is not a keyword character
  /// (`hop.jump_regex.regex_by_word_start`).
  static func wordStartLocations(in text: String, range: NSRange) -> [Int] {
    let nsString = text as NSString
    guard nsString.length > 0 else { return [] }
    let lower = min(max(0, range.location), nsString.length)
    let upper = min(lower + max(0, range.length), nsString.length)
    var locations: [Int] = []
    var previousIsWord = lower > 0 && isWordCharacter(nsString.character(at: lower - 1))
    var offset = lower
    while offset < upper {
      let composed = nsString.rangeOfComposedCharacterSequence(at: offset)
      let isWord = isWordCharacter(nsString.character(at: composed.location))
      if isWord, !previousIsWord {
        locations.append(composed.location)
      }
      previousIsWord = isWord
      offset = composed.location + composed.length
    }
    return locations
  }

  private static func isWordCharacter(_ utf16Unit: unichar) -> Bool {
    guard let scalar = Unicode.Scalar(utf16Unit) else { return true }
    return wordCharacters.contains(scalar)
  }

  // MARK: - Label permutations (hop perm.lua, TrieBacktrackFilling)

  private final class TrieNode {
    let key: Character
    var children: [TrieNode] = []
    init(key: Character) { self.key = key }
  }

  /// The first `count` label sequences hop generates for `keys`, in trie
  /// order. Prefix-free by construction: a key used as a longer label's
  /// prefix never also stands alone. Later keys in the charset are expanded
  /// into multi-character labels first, so the earliest keys stay
  /// single-character the longest (hop's backtrack filling).
  static func labelPermutations(count: Int, keys: [Character] = labelKeys) -> [String] {
    guard count > 0, keys.count >= 2 else { return [] }
    var root: [TrieNode] = []
    var pointer: [Int] = []
    for _ in 0..<count {
      nextPermutation(keys: keys, root: &root, pointer: &pointer)
    }
    var perms: [String] = []
    for node in root {
      collectPermutations(node, prefix: "", into: &perms)
    }
    return perms
  }

  private static func nextPermutation(keys: [Character], root: inout [TrieNode], pointer: inout [Int]) {
    if root.isEmpty {
      root = [TrieNode(key: keys[0])]
      return
    }
    let lastKey = layerNodes(root: root, pointer: pointer).last?.key
    let nextKeyIndex = lastKey.flatMap { keys.firstIndex(of: $0) }.map { $0 + 1 }
    if let nextKeyIndex, nextKeyIndex < keys.count {
      appendKey(keys[nextKeyIndex], root: &root, pointer: pointer)
      return
    }
    // Backtrack (hop perm.lua next_perm): move to an earlier sibling branch
    // when one exists, refilling deeper pointer components with the last
    // index; otherwise grow a fresh layer under the final leaf. Both exits
    // convert a single-character leaf into a prefix carrying the first two
    // keys, which is what nets exactly one new label per call.
    let maxDepth = pointer.count
    while !pointer.isEmpty {
      let lastIndex = pointer[pointer.count - 1]
      if lastIndex > 0 {
        pointer[pointer.count - 1] = lastIndex - 1
        pointer = maintainDeepPointer(depth: maxDepth, fill: keys.count - 1, pointer: pointer)
        appendKey(keys[0], root: &root, pointer: pointer)
        appendKey(keys[1], root: &root, pointer: pointer)
        return
      }
      pointer.removeLast()
    }
    pointer = maintainDeepPointer(depth: maxDepth, fill: keys.count - 1, pointer: pointer)
    pointer.append(root.count - 1)
    appendKey(keys[0], root: &root, pointer: pointer)
    appendKey(keys[1], root: &root, pointer: pointer)
  }

  private static func maintainDeepPointer(depth: Int, fill: Int, pointer: [Int]) -> [Int] {
    var extended = pointer
    while extended.count < depth {
      extended.append(fill)
    }
    return extended
  }

  private static func layerNodes(root: [TrieNode], pointer: [Int]) -> [TrieNode] {
    guard let first = pointer.first, root.indices.contains(first) else {
      return pointer.isEmpty ? root : []
    }
    var node = root[first]
    for index in pointer.dropFirst() {
      guard node.children.indices.contains(index) else { return [] }
      node = node.children[index]
    }
    return node.children
  }

  private static func appendKey(_ key: Character, root: inout [TrieNode], pointer: [Int]) {
    guard let first = pointer.first else {
      root.append(TrieNode(key: key))
      return
    }
    guard root.indices.contains(first) else { return }
    var node = root[first]
    for index in pointer.dropFirst() {
      guard node.children.indices.contains(index) else { return }
      node = node.children[index]
    }
    node.children.append(TrieNode(key: key))
  }

  private static func collectPermutations(_ node: TrieNode, prefix: String, into perms: inout [String]) {
    let path = prefix + String(node.key)
    if node.children.isEmpty {
      perms.append(path)
      return
    }
    for child in node.children {
      collectPermutations(child, prefix: path, into: &perms)
    }
  }

  // MARK: - Hint assignment (hop hint.lua create_hints + jump_target scoring)

  /// Labeled hints for `targetLocations` (document order preserved). The
  /// nearest targets by Manhattan distance (`10 * |drow| + |dcol|`, hop's
  /// default `x_bias`) receive the earliest labels in trie order.
  static func hints(
    targetLocations: [Int],
    cursorLocation: Int,
    text: String,
    keys: [Character] = labelKeys
  ) -> [VimFlashTarget] {
    guard !targetLocations.isEmpty else { return [] }
    let cursor = position(of: cursorLocation, in: text)
    let scored = targetLocations.enumerated().map { index, location -> (index: Int, score: Int) in
      let position = position(of: location, in: text)
      return (index, 10 * abs(position.row - cursor.row) + abs(position.col - cursor.col))
    }
    let ordered = scored.sorted { lhs, rhs in
      lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score
    }
    let labels = labelPermutations(count: targetLocations.count, keys: keys)
    guard labels.count == targetLocations.count else { return [] }
    var assigned = [String](repeating: "", count: targetLocations.count)
    for (rank, entry) in ordered.enumerated() {
      assigned[entry.index] = labels[rank]
    }
    return zip(targetLocations, assigned).map { VimFlashTarget(location: $0, label: $1) }
  }

  // MARK: - Positions

  static func position(of location: Int, in text: String) -> Position {
    let nsString = text as NSString
    let clamped = min(max(0, location), nsString.length)
    var row = 0
    var lineStart = 0
    while lineStart < clamped {
      let line = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
      let end = line.location + line.length
      if clamped < end || end == lineStart { break }
      lineStart = end
      row += 1
    }
    return Position(row: row, col: clamped - lineStart)
  }

  // MARK: - Touching-run alternation (David's hop.lua set_hint_extmarks wrapper)

  /// For hints at `positions` with current (possibly narrowed) `labels`,
  /// returns which hints paint the alternate color. Two labels "touch" when
  /// they share a row and the second starts at or before the first label's
  /// exclusive end column; every other hint in a touching run alternates so
  /// adjacent labels separate by eye. Recomputed on every narrowing
  /// keypress, matching the nvim wrapper.
  static func alternateFlags(positions: [Position], labels: [String]) -> [Bool] {
    guard positions.count == labels.count, positions.count > 1 else {
      return positions.map { _ in false }
    }
    let order = positions.indices.sorted { lhs, rhs in
      if positions[lhs].row != positions[rhs].row { return positions[lhs].row < positions[rhs].row }
      if positions[lhs].col != positions[rhs].col { return positions[lhs].col < positions[rhs].col }
      return lhs < rhs
    }
    var flags = [Bool](repeating: false, count: positions.count)
    var runRow = -1
    var runEnd = Int.min
    var previousWasAlternate = false
    for index in order {
      let position = positions[index]
      let touching = runEnd != .min && position.row == runRow && position.col <= runEnd
      let isAlternate = touching && !previousWasAlternate
      flags[index] = isAlternate
      previousWasAlternate = isAlternate
      runRow = position.row
      runEnd = position.col + labels[index].count
    }
    return flags
  }
}
