import Foundation

/// Learns which result the user picks so frequent choices float up, and a query that was
/// answered with a given item before ("ch" → Chrome) keeps returning it first.
public final class UsageStore: @unchecked Sendable {
  struct Data: Codable {
    var counts: [String: Int] = [:]
    /// Normalized query → id chosen most recently for it.
    var choices: [String: String] = [:]
  }

  private let url: URL?
  private let lock = NSLock()
  private var data = Data()

  /// Pass nil for an in-memory store (tests).
  public init(url: URL?) {
    self.url = url
    if let url, let raw = try? Foundation.Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode(Data.self, from: raw)
    {
      data = decoded
    }
  }

  public func record(query: String, id: String) {
    lock.withLock {
      data.counts[id, default: 0] += 1
      let key = TextNormalizer.compact(query)
      if !key.isEmpty { data.choices[key] = id }
    }
    save()
  }

  public func boost(query: String, id: String) -> Double {
    lock.withLock {
      var value = log2(Double(1 + data.counts[id, default: 0])) * 25
      if data.choices[TextNormalizer.compact(query)] == id { value += 500 }
      return value
    }
  }

  private func save() {
    guard let url else { return }
    let raw = lock.withLock { try? JSONEncoder().encode(data) }
    guard let raw else { return }
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? raw.write(to: url, options: .atomic)
  }
}
