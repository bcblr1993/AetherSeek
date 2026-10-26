import Foundation

/// Launcher rows for installed applications. The app refreshes `entries` when folders change.
public final class AppProvider: ResultProvider, @unchecked Sendable {
  private let lock = NSLock()
  private var _entries: [AppEntry] = []
  private let usage: UsageStore

  public init(usage: UsageStore) {
    self.usage = usage
  }

  public var entries: [AppEntry] {
    get { lock.withLock { _entries } }
    set { lock.withLock { _entries = newValue } }
  }

  public func results(for query: String) async -> [SearchResult] {
    entries.compactMap { entry in
      guard let score = Matcher.score(query, entry.key) else { return nil }
      return SearchResult(
        id: "app:" + (entry.bundleID ?? entry.url.path),
        title: entry.displayName,
        subtitle: entry.url.path,
        icon: .file(entry.url),
        action: .open(entry.url),
        score: score + usage.boost(query: query, id: "app:" + (entry.bundleID ?? entry.url.path)))
    }
  }
}
