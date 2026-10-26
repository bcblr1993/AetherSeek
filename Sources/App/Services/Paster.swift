import AppKit
import Carbon.HIToolbox

/// Inserts text into whatever app has focus by borrowing the pasteboard for one ⌘V,
/// then puts the user's clipboard back.
@MainActor
enum Paster {
  /// Marks events we synthesize so our own keyboard tap ignores them.
  nonisolated static let syntheticMarker: Int64 = 0x4165_536B

  /// nspasteboard.org conventions: clipboard managers skip transient items and hide concealed ones.
  static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
  static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

  static func insert(_ text: String, deletingBackward: Int = 0, cursorOffsetFromEnd: Int = 0, concealed: Bool = false) async {
    for _ in 0..<deletingBackward { tap(UInt16(kVK_Delete)) }
    if deletingBackward > 0 { try? await Task.sleep(for: .milliseconds(30)) }

    let pasteboard = NSPasteboard.general
    let saved = snapshot(pasteboard)
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    pasteboard.setString("", forType: transientType)
    if concealed { pasteboard.setString("", forType: concealedType) }
    let ourChange = pasteboard.changeCount

    tap(UInt16(kVK_ANSI_V), flags: .maskCommand)
    if cursorOffsetFromEnd > 0 {
      try? await Task.sleep(for: .milliseconds(50))
      for _ in 0..<cursorOffsetFromEnd { tap(UInt16(kVK_LeftArrow)) }
    }

    // Slow apps read the pasteboard well after ⌘V arrives. Restore in the background so the
    // caller can release held keystrokes right away.
    Task {
      try? await Task.sleep(for: .milliseconds(400))
      if pasteboard.changeCount == ourChange { restore(saved, to: pasteboard) }
    }
  }

  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  static func tap(_ key: UInt16, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .privateState)
    for down in [true, false] {
      guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
      event.flags = flags
      event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
      event.post(tap: .cghidEventTap)
    }
  }

  private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
    (pasteboard.pasteboardItems ?? []).map { item in
      var data: [NSPasteboard.PasteboardType: Data] = [:]
      for type in item.types { data[type] = item.data(forType: type) }
      return data
    }
  }

  private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    guard !items.isEmpty else { return }
    pasteboard.writeObjects(
      items.map { values in
        let item = NSPasteboardItem()
        for (type, data) in values { item.setData(data, forType: type) }
        return item
      })
  }
}
