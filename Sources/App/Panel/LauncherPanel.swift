import AppKit
import SwiftUI

/// Borderless floating panel that takes keyboard focus without activating AetherSeek, so the
/// app the user was in stays frontmost and receives pasted snippets.
final class LauncherPanel: NSPanel {
  var onResignKey: () -> Void = {}
  /// SwiftUI focus only sticks once the window is key, so focus requests wait for this.
  var onBecomeKey: () -> Void = {}

  init<Content: View>(rootView: Content) {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 72),
      styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
      backing: .buffered, defer: true)
    isFloatingPanel = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    isMovableByWindowBackground = true
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    animationBehavior = .utilityWindow

    let controller = NSHostingController(rootView: rootView)
    controller.sizingOptions = .preferredContentSize
    controller.view.wantsLayer = true
    controller.view.layer?.backgroundColor = .clear
    contentViewController = controller
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  /// Results grow and shrink below the search field; keep the top edge where the user saw it,
  /// and stay centered when SwiftUI settles on a different width.
  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    var frame = frameRect
    if frame.height != self.frame.height {
      frame.origin.y = self.frame.maxY - frame.height
    }
    if frame.width != self.frame.width {
      frame.origin.x = self.frame.midX - frame.width / 2
    }
    super.setFrame(frame, display: flag)
  }

  override func becomeKey() {
    super.becomeKey()
    onBecomeKey()
    // SwiftUI focus goes through NSApp.keyWindow, which is nil while our app is inactive (the
    // normal case when summoned by hot key), so put the caret in the field directly too.
    focusTextField()
    DispatchQueue.main.async { [weak self] in self?.focusTextField() }
  }

  private func focusTextField() {
    guard let field = Self.firstTextField(in: contentView), firstResponder !== field.currentEditor() else { return }
    makeFirstResponder(field)
  }

  private static func firstTextField(in view: NSView?) -> NSTextField? {
    guard let view else { return nil }
    if let field = view as? NSTextField, field.isEditable { return field }
    for subview in view.subviews {
      if let field = firstTextField(in: subview) { return field }
    }
    return nil
  }

  override func resignKey() {
    super.resignKey()
    onResignKey()
  }

  /// A menu-bar app has no Edit menu, so ⌘V and friends would never reach the text field.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let action: Selector? =
      switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
      case (.command, "x"): #selector(NSText.cut(_:))
      case (.command, "c"): #selector(NSText.copy(_:))
      case (.command, "v"): #selector(NSText.paste(_:))
      case (.command, "a"): #selector(NSText.selectAll(_:))
      case (.command, "z"): Selector(("undo:"))
      case ([.command, .shift], "z"): Selector(("redo:"))
      default: nil
      }
    // Not NSApp.sendAction: our app is never active, so it has no key window to start from.
    if let action, let responder = firstResponder, responder.tryToPerform(action, with: self) {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func cancelOperation(_ sender: Any?) {
    orderOut(nil)
  }

  /// Horizontally centered on the screen with the mouse, a quarter of the way down.
  func present() {
    let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    if let visible = screen?.visibleFrame {
      let top = visible.maxY - visible.height * 0.22
      setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: top - frame.height))
    }
    makeKeyAndOrderFront(nil)
  }
}
