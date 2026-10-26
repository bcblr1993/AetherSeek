import ApplicationServices

/// Reads the text just before the caret in the focused field of any app, via Accessibility.
enum FocusedText {
  /// nil when the focused app doesn't expose its text (terminals, many Electron apps).
  static func beforeCaret(length: Int) -> String? {
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { return nil }
    let element = focused as! AXUIElement

    var rangeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
      let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID()
    else { return nil }
    var selection = CFRange()
    guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection) else { return nil }

    // AX ranges count UTF-16 units; ask for a few extra and trim by characters below.
    let start = max(0, selection.location - length * 2)
    var wanted = CFRange(location: start, length: selection.location - start)
    guard let wantedValue = AXValueCreate(.cfRange, &wanted) else { return nil }
    var text: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element, kAXStringForRangeParameterizedAttribute as CFString, wantedValue, &text) == .success,
      let string = text as? String
    else { return nil }
    return String(string.suffix(length))
  }
}
