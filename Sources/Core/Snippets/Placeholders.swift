import Foundation

/// Fills `{clipboard}`, `{date}`, `{time}`, `{datetime}`, `{isodate}`, `{uuid}` and `{cursor}`.
/// Date tokens take an optional style (`short|medium|long|full`) or, for `isodate`, a
/// format: `{isodate:yyyy-MM-dd}`. Unknown tokens are left untouched.
public enum Placeholders {
  public struct Context: Sendable {
    public var clipboard: String
    public var now: Date
    public var locale: Locale
    public var timeZone: TimeZone

    public init(
      clipboard: String = "", now: Date = .now, locale: Locale = .current,
      timeZone: TimeZone = .current
    ) {
      self.clipboard = clipboard
      self.now = now
      self.locale = locale
      self.timeZone = timeZone
    }
  }

  public struct Rendered: Equatable, Sendable {
    public var text: String
    /// Characters between `{cursor}` and the end, i.e. how far to move left after inserting.
    public var cursorOffsetFromEnd: Int
  }

  public static func usesClipboard(_ template: String) -> Bool {
    template.contains("{clipboard}")
  }

  public static func render(_ template: String, context: Context) -> Rendered {
    var output = ""
    var cursorIndex: Int?
    var rest = Substring(template)
    while let open = rest.firstIndex(of: "{") {
      output += rest[..<open]
      guard let close = rest[open...].firstIndex(of: "}") else {
        rest = rest[open...]
        break
      }
      let token = String(rest[rest.index(after: open)..<close])
      if token == "cursor" {
        cursorIndex = output.count
      } else if let value = value(for: token, context: context) {
        output += value
      } else {
        output += rest[open...close]
      }
      rest = rest[rest.index(after: close)...]
    }
    output += rest
    return Rendered(text: output, cursorOffsetFromEnd: cursorIndex.map { output.count - $0 } ?? 0)
  }

  static func value(for token: String, context: Context) -> String? {
    let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
    let name = parts[0]
    let argument = parts.count > 1 ? parts[1] : nil
    switch name {
    case "clipboard":
      return argument == nil ? context.clipboard : nil
    case "uuid":
      return UUID().uuidString
    case "date", "time", "datetime":
      let formatter = DateFormatter()
      formatter.locale = context.locale
      formatter.timeZone = context.timeZone
      let style = argument.flatMap(Self.style) ?? .medium
      formatter.dateStyle = name == "time" ? .none : style
      formatter.timeStyle = name == "date" ? .none : (argument == nil ? .short : style)
      return formatter.string(from: context.now)
    case "isodate":
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = context.timeZone
      formatter.dateFormat = argument ?? "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
      return formatter.string(from: context.now)
    default:
      return nil
    }
  }

  static func style(_ name: String) -> DateFormatter.Style? {
    switch name {
    case "short": .short
    case "medium": .medium
    case "long": .long
    case "full": .full
    default: nil
    }
  }
}
