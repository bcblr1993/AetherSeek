import SwiftUI

@main
struct AetherSeekApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate

  var body: some Scene {
    MenuBarExtra("AetherSeek", systemImage: "sparkle.magnifyingglass") {
      MenuContent(controller: delegate.controller)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let controller = AppController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    controller.start()
  }

  /// Opening the app again from Finder or Spotlight brings up the launcher.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    controller.toggleLauncher()
    return false
  }
}

struct MenuContent: View {
  let controller: AppController

  var body: some View {
    Button("Show AetherSeek  \(controller.settings.launcherHotKey.displayString)") { controller.toggleLauncher() }
    Button("Snippet Viewer  \(controller.settings.snippetViewerHotKey.displayString)") { controller.toggleSnippetViewer() }
    Divider()
    if !controller.isAccessibilityGranted {
      Button("Grant Accessibility Access…") { controller.showOnboarding() }
    }
    Button("Settings…") { controller.showSettings() }
      .keyboardShortcut(",")
    Divider()
    Button("Quit AetherSeek") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }
}
