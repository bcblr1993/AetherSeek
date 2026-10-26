import Foundation

/// A user-assignable global shortcut: a virtual key code (kVK_*) plus modifiers.
public struct KeyCombo: Codable, Hashable, Sendable {
  public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
  }

  public var keyCode: UInt32
  public var modifiers: Modifiers

  public init(keyCode: UInt32, modifiers: Modifiers) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  /// ⌥Space — Alfred's default, and ⌘Space stays with Spotlight.
  public static let defaultLauncher = KeyCombo(keyCode: 49, modifiers: .option)
  /// ⌃⌥⌘V for the snippet viewer.
  public static let defaultSnippetViewer = KeyCombo(
    keyCode: 9, modifiers: [.control, .option, .command])

  /// A global shortcut without any modifier would swallow ordinary typing (F-keys excepted).
  public var isValid: Bool {
    !modifiers.isEmpty || Self.functionKeys.contains(keyCode)
  }

  /// "⌃⌥⇧⌘K", in the order macOS menus use.
  public var displayString: String {
    var text = ""
    if modifiers.contains(.control) { text += "⌃" }
    if modifiers.contains(.option) { text += "⌥" }
    if modifiers.contains(.shift) { text += "⇧" }
    if modifiers.contains(.command) { text += "⌘" }
    return text + (Self.keyNames[keyCode] ?? "#\(keyCode)")
  }

  static let functionKeys: Set<UInt32> = [
    122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106,
  ]

  /// ANSI layout names; the app may override letters with the active layout's characters.
  public static let keyNames: [UInt32: String] = {
    var names: [UInt32: String] = [
      49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 117: "⌦",
      123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
      122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
      101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
      106: "F16",
    ]
    let ansi: [(UInt32, String)] = [
      (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"),
      (34, "I"), (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"), (31, "O"), (35, "P"),
      (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"), (9, "V"), (13, "W"), (7, "X"),
      (16, "Y"), (6, "Z"), (29, "0"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"),
      (22, "6"), (26, "7"), (28, "8"), (25, "9"), (50, "`"), (27, "-"), (24, "="), (33, "["),
      (30, "]"), (42, "\\"), (41, ";"), (39, "'"), (43, ","), (47, "."), (44, "/"),
    ]
    for (code, name) in ansi { names[code] = name }
    return names
  }()
}
