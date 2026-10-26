import Foundation

/// Watches typed characters and reports when the text just typed ends with a snippet trigger.
/// Pure state machine; the app feeds it from a keyboard event tap and performs the replacement.
public struct ExpansionEngine: Sendable {
  public struct Match: Equatable, Sendable {
    public var snippet: Snippet
    /// Characters to delete before inserting the expansion.
    public var triggerLength: Int
  }

  private var triggers: [String: Snippet] = [:]
  private var maxLength = 0
  private var buffer: [Character] = []

  public init(triggers: [String: Snippet] = [:]) {
    update(triggers: triggers)
  }

  public mutating func update(triggers: [String: Snippet]) {
    self.triggers = triggers
    maxLength = triggers.keys.map(\.count).max() ?? 0
    reset()
  }

  /// Anything that moves the caret or changes focus makes the buffer meaningless.
  public mutating func reset() {
    buffer.removeAll(keepingCapacity: true)
  }

  public mutating func deleteBackward() {
    if !buffer.isEmpty { buffer.removeLast() }
  }

  /// Feeds what one key press typed. Returns the longest trigger that now ends the buffer.
  public mutating func type(_ text: String) -> Match? {
    guard maxLength > 0 else { return nil }
    for character in text {
      if character.isNewline {
        reset()
        continue
      }
      buffer.append(character)
    }
    if buffer.count > maxLength { buffer.removeFirst(buffer.count - maxLength) }
    var length = min(buffer.count, maxLength)
    while length > 0 {
      let tail = String(buffer.suffix(length))
      if let snippet = triggers[tail] {
        reset()
        return Match(snippet: snippet, triggerLength: tail.count)
      }
      length -= 1
    }
    return nil
  }
}
