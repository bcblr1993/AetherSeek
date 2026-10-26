import os

/// `log stream --predicate 'subsystem == "com.aethernative.AetherSeek"'` shows these.
enum Log {
  static let expansion = Logger(subsystem: "com.aethernative.AetherSeek", category: "expansion")
  static let snippets = Logger(subsystem: "com.aethernative.AetherSeek", category: "snippets")
}
