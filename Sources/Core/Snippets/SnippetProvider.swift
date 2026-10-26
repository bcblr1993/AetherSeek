import Foundation

/// Snippet rows, for `snip <text>` in the launcher and for the snippet viewer.
public final class SnippetProvider: ResultProvider, @unchecked Sendable {
  public static let keyword = "snip"

  private let lock = NSLock()
  private var _index = SnippetIndex(groups: [])
  /// Viewer mode answers every query; launcher mode only after the "snip " keyword.
  private let requiresKeyword: Bool

  public init(requiresKeyword: Bool) {
    self.requiresKeyword = requiresKeyword
  }

  public var index: SnippetIndex {
    get { lock.withLock { _index } }
    set { lock.withLock { _index = newValue } }
  }

  public func results(for query: String) async -> [SearchResult] {
    let text: String
    if requiresKeyword {
      guard let argument = argument(of: query, keyword: Self.keyword) else { return [] }
      text = argument
    } else {
      text = query.trimmingCharacters(in: .whitespaces)
    }
    return index.entries.enumerated().compactMap { position, entry in
      let snippet = entry.snippet
      let score: Double
      if text.isEmpty {
        // Keep the group/name order when nothing is typed.
        score = 1 - Double(position) / Double(max(index.entries.count, 1))
      } else {
        var names = [(snippet.name, Phonetics.Language.unknown)]
        if let trigger = entry.trigger { names.append((trigger, .unknown)) }
        names.append((snippet.keyword, .unknown))
        if let match = Matcher.score(text, SearchKey(names: names)) {
          score = match
        } else if !snippet.isSensitive,
          TextNormalizer.normalize(snippet.content).contains(TextNormalizer.normalize(text))
        {
          score = 200
        } else {
          return nil
        }
      }
      return SearchResult(
        id: "snippet:" + snippet.id.uuidString,
        title: snippet.name.isEmpty ? (entry.trigger ?? "") : snippet.name,
        subtitle: [entry.trigger, entry.groupName].compactMap(\.self).joined(separator: " · "),
        icon: .symbol(snippet.isSensitive ? "lock.doc" : "text.quote"),
        action: .pasteSnippet(snippet.id),
        score: score)
    }
  }
}
