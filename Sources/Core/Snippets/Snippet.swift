import Foundation

public struct Snippet: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var name: String
  /// Typed after the group prefix to expand, e.g. "phone" in group ":" → ":phone".
  public var keyword: String
  /// Plain text with placeholders. Empty for sensitive snippets: their content lives in the Keychain.
  public var content: String
  public var isSensitive: Bool
  public var autoExpands: Bool

  public init(
    id: UUID = UUID(), name: String, keyword: String, content: String,
    isSensitive: Bool = false, autoExpands: Bool = true
  ) {
    self.id = id
    self.name = name
    self.keyword = keyword
    self.content = content
    self.isSensitive = isSensitive
    self.autoExpands = autoExpands
  }

  enum CodingKeys: String, CodingKey {
    case id, name, keyword, content, isSensitive, autoExpands
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    keyword = try container.decodeIfPresent(String.self, forKey: .keyword) ?? ""
    content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
    isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
    autoExpands = try container.decodeIfPresent(Bool.self, forKey: .autoExpands) ?? true
  }
}

public struct SnippetGroup: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var name: String
  /// Shared by every keyword in the group, so ":" turns "phone" into ":phone".
  public var prefix: String
  public var suffix: String
  public var isEnabled: Bool
  public var snippets: [Snippet]

  public init(
    id: UUID = UUID(), name: String, prefix: String = "", suffix: String = "",
    isEnabled: Bool = true, snippets: [Snippet] = []
  ) {
    self.id = id
    self.name = name
    self.prefix = prefix
    self.suffix = suffix
    self.isEnabled = isEnabled
    self.snippets = snippets
  }

  public func trigger(for snippet: Snippet) -> String? {
    snippet.keyword.isEmpty ? nil : prefix + snippet.keyword + suffix
  }
}

/// What expansion and search see: enabled snippets with their full trigger strings.
public struct SnippetIndex: Sendable {
  public struct Entry: Sendable, Hashable {
    public var snippet: Snippet
    public var groupID: UUID
    public var groupName: String
    public var trigger: String?
  }

  public enum Problem: Hashable, Sendable {
    /// Two snippets share a trigger; only one can ever expand.
    case duplicate(String, [UUID])
    /// A shorter trigger fires before a longer one can be finished: "id" blocks "idea".
    case shadowed(short: String, long: String, UUID)
  }

  public private(set) var entries: [Entry] = []

  public init(groups: [SnippetGroup]) {
    for group in groups where group.isEnabled {
      for snippet in group.snippets {
        entries.append(
          Entry(
            snippet: snippet, groupID: group.id, groupName: group.name,
            trigger: group.trigger(for: snippet)))
      }
    }
  }

  public var expandable: [String: Snippet] {
    var map: [String: Snippet] = [:]
    for entry in entries where entry.snippet.autoExpands {
      if let trigger = entry.trigger, map[trigger] == nil { map[trigger] = entry.snippet }
    }
    return map
  }

  public var problems: [Problem] {
    var byTrigger: [String: [UUID]] = [:]
    for entry in entries where entry.snippet.autoExpands {
      if let trigger = entry.trigger { byTrigger[trigger, default: []].append(entry.snippet.id) }
    }
    var result: [Problem] = []
    for (trigger, ids) in byTrigger.sorted(by: { $0.key < $1.key }) where ids.count > 1 {
      result.append(.duplicate(trigger, ids))
    }
    let triggers = byTrigger.keys.sorted()
    for short in triggers {
      for long in triggers where long != short && long.hasPrefix(short) {
        result.append(.shadowed(short: short, long: long, byTrigger[long]![0]))
      }
    }
    return result
  }
}
