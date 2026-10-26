import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Turns a key code plus the event's own modifier flags into text with the active keyboard
/// layout. `CGEvent.keyboardGetUnicodeString` was observed to lag the shift state by a key
/// (":" read as ";", "d" as "D"), which breaks trigger matching.
final class KeyTranslator: @unchecked Sendable {
  private let lock = NSLock()
  private var layout: Data?
  private var keyboardType: UInt32 = 0
  private var observer: NSObjectProtocol?

  /// Text Input Sources must be read on main; translation itself is safe on any thread.
  @MainActor init() {
    refresh()
    observer = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
  }

  deinit {
    if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
  }

  /// Uses the layout under any input method (拼音 sits on top of ABC), which always has key data.
  @MainActor func refresh() {
    let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
    let raw = source.flatMap { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) }
    let data = raw.map { Unmanaged<CFData>.fromOpaque($0).takeUnretainedValue() as Data }
    let type = UInt32(LMGetKbdType())
    lock.withLock {
      layout = data
      keyboardType = type
    }
  }

  func text(keyCode: UInt16, flags: CGEventFlags) -> String? {
    guard let (layout, keyboardType) = lock.withLock({ layout.map { ($0, keyboardType) } }) else { return nil }
    var carbon: UInt32 = 0
    if flags.contains(.maskShift) { carbon |= UInt32(shiftKey) }
    if flags.contains(.maskAlternate) { carbon |= UInt32(optionKey) }
    if flags.contains(.maskAlphaShift) { carbon |= UInt32(alphaLock) }
    var deadKeys: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 8)
    let status = layout.withUnsafeBytes { buffer in
      UCKeyTranslate(
        buffer.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self), keyCode, UInt16(kUCKeyActionDown),
        (carbon >> 8) & 0xFF, keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys,
        characters.count, &length, &characters)
    }
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: length)
  }
}
