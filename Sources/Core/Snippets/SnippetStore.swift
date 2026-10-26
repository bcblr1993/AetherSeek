import Foundation

/// Holds the content of sensitive snippets outside the JSON files.
public protocol SecretStore: Sendable {
  func read(_ id: UUID) -> String?
  func write(_ value: String, for id: UUID) throws
  func delete(_ id: UUID)
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [UUID: String] = [:]

  public init() {}

  public func read(_ id: UUID) -> String? { lock.withLock { values[id] } }
  public func write(_ value: String, for id: UUID) throws { lock.withLock { values[id] = value } }
  public func delete(_ id: UUID) { _ = lock.withLock { values.removeValue(forKey: id) } }
}

/// One `<group id>.json` per group in a folder, so a synced folder (iCloud Drive) merges
/// edits per group and diffs stay readable.
public struct SnippetStore: Sendable {
  public let directory: URL
  public let secrets: any SecretStore

  public init(directory: URL, secrets: any SecretStore) {
    self.directory = directory
    self.secrets = secrets
  }

  public func load() throws -> [SnippetGroup] {
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    let decoder = JSONDecoder()
    var groups: [SnippetGroup] = []
    for file in files where file.pathExtension == "json" {
      // A half-synced or hand-broken file shouldn't take every other group down with it.
      guard let data = try? Data(contentsOf: file),
        let group = try? decoder.decode(SnippetGroup.self, from: data)
      else { continue }
      groups.append(group)
    }
    return groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /// Writes one group. Sensitive content moves to the secret store and is blanked on disk.
  public func save(_ group: SnippetGroup) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var stored = group
    for index in stored.snippets.indices where stored.snippets[index].isSensitive {
      let snippet = stored.snippets[index]
      if !snippet.content.isEmpty {
        try secrets.write(snippet.content, for: snippet.id)
      }
      stored.snippets[index].content = ""
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(stored).write(to: url(for: group.id), options: .atomic)
  }

  public func delete(_ group: SnippetGroup) throws {
    for snippet in group.snippets where snippet.isSensitive { secrets.delete(snippet.id) }
    let file = url(for: group.id)
    if FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    }
  }

  /// The text a snippet inserts, fetching sensitive content on demand.
  public func content(of snippet: Snippet) -> String {
    snippet.isSensitive ? (secrets.read(snippet.id) ?? "") : snippet.content
  }

  func url(for id: UUID) -> URL {
    directory.appending(path: id.uuidString + ".json")
  }
}
