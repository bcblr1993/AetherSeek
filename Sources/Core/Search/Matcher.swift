import Foundation

/// Everything a query can be compared against for one item, computed once at index time.
public struct SearchKey: Sendable {
  struct Form: Sendable {
    var text: String
    var weight: Double
    var isInitials: Bool
  }

  var forms: [Form] = []
  /// Normalized words of the original names, for word-start matches ("code" → "Visual Studio Code").
  var words: [String] = []

  public init(names: [(String, Phonetics.Language)]) {
    for (name, language) in names where !name.isEmpty {
      let compact = TextNormalizer.compact(name)
      append(compact, weight: 1, isInitials: false)
      let parts = Self.split(name)
      words += parts
      if parts.count > 1 {
        append(String(parts.compactMap(\.first)), weight: 0.9, isInitials: true)
      }
      for reading in Phonetics.readings(of: name, language: language) {
        append(reading.full, weight: 0.95, isInitials: false)
        if reading.initials.count > 1 {
          append(reading.initials, weight: 0.9, isInitials: true)
        }
      }
    }
  }

  public init(_ names: String...) {
    self.init(names: names.map { ($0, .unknown) })
  }

  private mutating func append(_ text: String, weight: Double, isInitials: Bool) {
    guard !text.isEmpty, !forms.contains(where: { $0.text == text && $0.isInitials == isInitials })
    else { return }
    forms.append(Form(text: text, weight: weight, isInitials: isInitials))
  }

  /// Splits on separators and camelCase humps: "PyCharm CE" → ["py", "charm", "ce"].
  static func split(_ name: String) -> [String] {
    var words: [String] = []
    var current = ""
    var previousWasLower = false
    for character in name {
      let scalarIsSeparator = character.unicodeScalars.allSatisfy {
        TextNormalizer.separators.contains($0)
      }
      if scalarIsSeparator {
        if !current.isEmpty { words.append(current) }
        current = ""
        previousWasLower = false
        continue
      }
      if character.isUppercase && previousWasLower && !current.isEmpty {
        words.append(current)
        current = ""
      }
      current.append(character)
      previousWasLower = character.isLowercase
    }
    if !current.isEmpty { words.append(current) }
    return words.map(TextNormalizer.compact).filter { !$0.isEmpty }
  }
}

public enum Matcher {
  /// Higher is better; nil means no match. Scores are only comparable within one query.
  public static func score(_ query: String, _ key: SearchKey) -> Double? {
    let query = TextNormalizer.compact(query)
    guard !query.isEmpty else { return nil }
    var best: Double?
    for form in key.forms {
      guard let raw = score(query, form.text, isInitials: form.isInitials) else { continue }
      let value = raw * form.weight
      if value > (best ?? 0) { best = value }
    }
    if let wordStart = key.words.first(where: { $0.hasPrefix(query) }) {
      let value = 750 - Double(wordStart.count - query.count)
      if value > (best ?? 0) { best = value }
    }
    return best
  }

  static func score(_ query: String, _ text: String, isInitials: Bool) -> Double? {
    if text == query { return isInitials ? 850 : 1000 }
    if text.hasPrefix(query) {
      return (isInitials ? 800 : 900) - Double(text.count - query.count)
    }
    if isInitials { return nil }
    if query.count >= 2, text.contains(query) { return 600 - Double(text.count - query.count) }
    if query.count >= 2, let fuzzy = subsequence(query, text) { return fuzzy }
    return nil
  }

  /// Ordered-subsequence match ("vscd" ⊂ "visualstudiocode"), rewarding runs and an anchored start.
  static func subsequence(_ query: String, _ text: String) -> Double? {
    let needle = Array(query)
    let haystack = Array(text)
    var index = 0
    var runs = 0
    var lastMatch = -2
    var firstMatch = -1
    for (position, character) in haystack.enumerated() where index < needle.count {
      guard character == needle[index] else { continue }
      if firstMatch < 0 { firstMatch = position }
      if position != lastMatch + 1 { runs += 1 }
      lastMatch = position
      index += 1
    }
    guard index == needle.count else { return nil }
    let anchored: Double = firstMatch == 0 ? 60 : 0
    return max(1, 400 + anchored - Double(runs) * 40 - Double(haystack.count - needle.count))
  }
}
