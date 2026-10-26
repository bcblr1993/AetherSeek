import AetherSeekCore
import AppKit
import Carbon.HIToolbox

/// Global keyboard tap that feeds typed characters to `ExpansionEngine` and replaces a
/// completed trigger with its snippet. Needs the Accessibility permission.
///
/// An active tap holds every key press system-wide until its callback returns, so it runs on
/// its own thread: a busy main thread must never make typing lag. Only matches hop to main.
final class ExpansionMonitor: @unchecked Sendable {
  private let lock = NSLock()
  private var engine = ExpansionEngine()
  private var tap: CFMachPort?
  private var thread: Thread?
  private var runLoop: CFRunLoop?
  private var observers: [NSObjectProtocol] = []
  private let translator: KeyTranslator
  /// Keys typed while an expansion is being performed. They are held back and replayed
  /// afterwards; otherwise fast typing lands between our deletes and the paste.
  private var held: [CGEvent]?
  private var expansionGeneration = 0

  @MainActor var excludedBundleIDs: Set<String> = []
  /// `verify` is true when an input method was active: the raw keys may still be sitting in a
  /// composition (or have become "：" instead of ":"), so the caller must check the document.
  /// The handler must call `finishExpansion()` when done, whether or not it inserted anything.
  @MainActor var expand: (_ match: ExpansionEngine.Match, _ verify: Bool) -> Void = { _, _ in }

  @MainActor init() {
    translator = KeyTranslator()
  }

  func update(_ index: SnippetIndex) {
    lock.withLock { engine.update(triggers: index.expandable) }
  }

  @MainActor @discardableResult
  func start() -> Bool {
    guard thread == nil else { return true }
    guard AXIsProcessTrusted() else {
      Log.expansion.error("Not starting: Accessibility not granted")
      return false
    }
    // The tap is created on the thread whose run loop services it; a tap created on main
    // and serviced elsewhere was observed to receive no events at all.
    let ready = DispatchSemaphore(value: 0)
    let thread = Thread { [weak self] in
      guard let self else {
        ready.signal()
        return
      }
      let mask: CGEventMask = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        .reduce(0) { $0 | (1 << $1.rawValue) }
      // An active (default) tap only needs Accessibility; a listen-only one would also need Input Monitoring.
      guard
        let tap = CGEvent.tapCreate(
          tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
          callback: { _, type, event, context in
            let monitor = Unmanaged<ExpansionMonitor>.fromOpaque(context!).takeUnretainedValue()
            return monitor.handle(type, event) ? Unmanaged.passUnretained(event) : nil
          }, userInfo: Unmanaged.passUnretained(self).toOpaque())
      else {
        ready.signal()
        return
      }
      let loop = CFRunLoopGetCurrent()
      CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
      lock.withLock {
        self.tap = tap
        runLoop = loop
      }
      ready.signal()
      CFRunLoopRun()
    }
    thread.name = "AetherSeek.ExpansionTap"
    thread.qualityOfService = .userInteractive
    thread.start()
    ready.wait()
    guard lock.withLock({ tap }) != nil else {
      Log.expansion.error("CGEvent.tapCreate failed")
      return false
    }
    self.thread = thread
    Log.expansion.info("Keyboard tap started")

    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.reset()
      })
    return true
  }

  @MainActor func stop() {
    if let tap = lock.withLock({ tap }) {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
    }
    if let loop = lock.withLock({ runLoop }) { CFRunLoopStop(loop) }
    thread = nil
    lock.withLock {
      tap = nil
      runLoop = nil
    }
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    observers.removeAll()
    reset()
  }

  private func reset() {
    lock.withLock { engine.reset() }
  }

  /// Releases keys held back during an expansion, in the order they were typed.
  @MainActor func finishExpansion() {
    let events = lock.withLock {
      defer { held = nil }
      return held ?? []
    }
    for event in events { event.post(tap: .cgSessionEventTap) }
  }

  /// Runs on the tap thread. Returns false to swallow the event.
  private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // The system turns slow taps off; turn ourselves back on.
      Log.expansion.notice("Tap was disabled (\(type.rawValue)); re-enabling")
      if let tap = lock.withLock({ tap }) { CGEvent.tapEnable(tap: tap, enable: true) }
      reset()
    case .keyDown:
      guard event.getIntegerValueField(.eventSourceUserData) != Paster.syntheticMarker else { return true }
      let holding = lock.withLock {
        guard held != nil, let copy = event.copy() else { return false }
        held?.append(copy)
        return true
      }
      if holding { return false }
      handleKey(event)
    default:
      // A click can move the caret anywhere.
      reset()
    }
    return true
  }

  private func handleKey(_ event: CGEvent) {
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    if IsSecureEventInputEnabled() || flags.contains(.maskCommand) || flags.contains(.maskControl)
      || Self.caretKeys.contains(keyCode)
    {
      reset()
      return
    }
    if keyCode == kVK_Delete {
      lock.withLock { engine.deleteBackward() }
      return
    }
    guard let text = translator.text(keyCode: UInt16(keyCode), flags: flags) else { return }
    let started: (ExpansionEngine.Match, Int)? = lock.withLock {
      guard let match = engine.type(text) else { return nil }
      held = []
      expansionGeneration += 1
      return (match, expansionGeneration)
    }
    guard let (match, generation) = started else { return }
    Log.expansion.debug("Matched snippet \(match.snippet.id, privacy: .public)")
    // Text Input Sources and NSWorkspace belong on main. Hopping there also lets this key
    // reach the app first, so our deletes are queued after it.
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        guard !self.isExcludedAppFrontmost() else { return self.finishExpansion() }
        self.expand(match, !Self.isPlainKeyboardLayout())
      }
    }
    // Never hold the keyboard hostage if an expansion stalls.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.lock.withLock({ self.expansionGeneration == generation && self.held != nil }) else { return }
        Log.expansion.notice("Expansion timed out; releasing held keys")
        self.finishExpansion()
      }
    }
  }

  @MainActor private func isExcludedAppFrontmost() -> Bool {
    guard !excludedBundleIDs.isEmpty, let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
    return excludedBundleIDs.contains(id)
  }

  /// Input methods (拼音, かな) hold typed keys in a composition, so the raw keys aren't text yet.
  @MainActor private static func isPlainKeyboardLayout() -> Bool {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceType)
    else { return true }
    let type = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
    return CFEqual(type, kTISTypeKeyboardLayout)
  }

  static let caretKeys: Set<Int> = [
    kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp,
    kVK_PageDown, kVK_Escape, kVK_Tab, kVK_Return, kVK_ANSI_KeypadEnter, kVK_ForwardDelete,
  ]
}
