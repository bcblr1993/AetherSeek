import AetherSeekCore
import AppKit
import SwiftUI

/// Click, then press the new shortcut. Esc cancels; a combination without modifiers is rejected.
struct KeyRecorder: View {
  @Binding var combo: KeyCombo
  /// Lets the owner pause global shortcuts so pressing the current one records it instead.
  var onRecordingChange: (Bool) -> Void = { _ in }

  @State private var isRecording = false
  @State private var monitor: Any?

  var body: some View {
    Button {
      isRecording ? stop() : start()
    } label: {
      Text(isRecording ? String(localized: "Type shortcut…") : combo.displayString)
        .monospaced()
        .frame(minWidth: 110)
    }
    .buttonStyle(.glass)
    .onDisappear(perform: stop)
  }

  private func start() {
    isRecording = true
    onRecordingChange(true)
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
        stop()
        return nil
      }
      let candidate = KeyCombo(
        keyCode: UInt32(event.keyCode), modifiers: HotKeyCenter.modifiers(event.modifierFlags))
      if candidate.isValid {
        combo = candidate
        stop()
      } else {
        NSSound.beep()
      }
      return nil
    }
  }

  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    if isRecording {
      isRecording = false
      onRecordingChange(false)
    }
  }
}
