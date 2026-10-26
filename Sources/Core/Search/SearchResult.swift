import Foundation

/// One row in the launcher. Providers fill these; the app knows how to draw and perform them.
public struct SearchResult: Identifiable, Sendable, Equatable {
  public enum Icon: Sendable, Equatable {
    case file(URL)
    case symbol(String)
  }

  public enum Action: Sendable, Equatable {
    case open(URL)
    case pasteSnippet(UUID)
    case copy(String)
    /// Rewrites the query, e.g. selecting a keyword item fills in "tr ".
    case complete(String)
  }

  /// Stable across searches; usage learning is keyed on it.
  public var id: String
  public var title: String
  public var subtitle: String
  public var icon: Icon
  public var action: Action
  public var score: Double

  public init(
    id: String, title: String, subtitle: String = "", icon: Icon, action: Action, score: Double
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.icon = icon
    self.action = action
    self.score = score
  }
}

/// Source of launcher rows. Workflows will plug in here in phase two.
public protocol ResultProvider: Sendable {
  func results(for query: String) async -> [SearchResult]
}

/// Splits "tr hello" into keyword "tr" and argument "hello"; nil when the keyword doesn't match.
public func argument(of query: String, keyword: String) -> String? {
  let trimmed = query.drop(while: \.isWhitespace)
  guard trimmed.lowercased().hasPrefix(keyword.lowercased() + " ") else { return nil }
  return String(trimmed.dropFirst(keyword.count + 1)).trimmingCharacters(in: .whitespaces)
}
