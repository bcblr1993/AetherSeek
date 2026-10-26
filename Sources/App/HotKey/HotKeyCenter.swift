import AetherSeekCore
import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts through Carbon's RegisterEventHotKey, which needs no Accessibility
/// permission and swallows the key so the frontmost app never sees it.
@MainActor
final class HotKeyCenter {
  enum Slot: UInt32 {
    case launcher = 1
    case snippetViewer = 2
  }

  private var refs: [Slot: EventHotKeyRef] = [:]
  private var handlers: [Slot: () -> Void] = [:]
  private var eventHandler: EventHandlerRef?
  /// "AeSk"
  private let signature: OSType = 0x4165_536B

  init() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, context in
        var id = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &id)
        let center = Unmanaged<HotKeyCenter>.fromOpaque(context!).takeUnretainedValue()
        MainActor.assumeIsolated { center.fire(id.id) }
        return noErr
      }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
  }

  /// Returns false when another app already owns the combination.
  @discardableResult
  func register(_ combo: KeyCombo, for slot: Slot, handler: @escaping () -> Void) -> Bool {
    unregister(slot)
    handlers[slot] = handler
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      combo.keyCode, Self.carbonFlags(combo.modifiers), EventHotKeyID(signature: signature, id: slot.rawValue),
      GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else { return false }
    refs[slot] = ref
    return true
  }

  func unregister(_ slot: Slot) {
    if let ref = refs.removeValue(forKey: slot) { UnregisterEventHotKey(ref) }
  }

  /// While recording a new shortcut the old ones must not fire.
  func suspend() {
    for (_, ref) in refs { UnregisterEventHotKey(ref) }
    refs.removeAll()
  }

  private func fire(_ id: UInt32) {
    guard let slot = Slot(rawValue: id) else { return }
    handlers[slot]?()
  }

  static func carbonFlags(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
    var flags = 0
    if modifiers.contains(.command) { flags |= cmdKey }
    if modifiers.contains(.option) { flags |= optionKey }
    if modifiers.contains(.control) { flags |= controlKey }
    if modifiers.contains(.shift) { flags |= shiftKey }
    return UInt32(flags)
  }

  static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
    var modifiers: KeyCombo.Modifiers = []
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.control) { modifiers.insert(.control) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    return modifiers
  }
}
