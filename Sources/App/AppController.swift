import AetherSeekCore
import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// Owns every long-lived piece of the app and wires them together.
@MainActor @Observable
final class AppController {
  let settings = AppSettings()
  let snippets: SnippetLibrary
  private(set) var isAccessibilityGranted = AXIsProcessTrusted()
  private(set) var hotKeyConflicts: Set<HotKeyCenter.Slot> = []

  @ObservationIgnored let launcher: SearchModel
  @ObservationIgnored let viewer: SearchModel
  @ObservationIgnored private let usage = UsageStore(url: AppSettings.supportDirectory.appending(path: "usage.json"))
  @ObservationIgnored private let apps: AppProvider
  @ObservationIgnored private let launcherSnippets = SnippetProvider(requiresKeyword: true)
  @ObservationIgnored private let viewerSnippets = SnippetProvider(requiresKeyword: false)
  @ObservationIgnored private let hotKeys = HotKeyCenter()
  @ObservationIgnored private let expansion = ExpansionMonitor()
  @ObservationIgnored private var launcherPanel: LauncherPanel?
  @ObservationIgnored private var viewerPanel: LauncherPanel?
  @ObservationIgnored private var settingsWindow: NSWindow?
  @ObservationIgnored private var onboardingWindow: NSWindow?
  @ObservationIgnored private var lastAppScan = Date.distantPast
  @ObservationIgnored private var permissionPoll: Task<Void, Never>?

  init() {
    snippets = SnippetLibrary(directory: settings.snippetDirectory)
    apps = AppProvider(usage: usage)
    launcher = SearchModel(mode: .launcher, providers: [apps, launcherSnippets, TranslationProvider()])
    viewer = SearchModel(mode: .snippets, providers: [viewerSnippets])
  }

  func start() {
    launcher.perform = { [unowned self] result, query in perform(result, query: query, from: launcherPanel) }
    viewer.perform = { [unowned self] result, query in perform(result, query: query, from: viewerPanel) }
    snippets.onChange = { [unowned self] index in
      launcherSnippets.index = index
      viewerSnippets.index = index
      expansion.update(index)
    }
    expansion.expand = { [unowned self] match, verify in expand(match, verify: verify) }
    snippets.reload()
    refreshApps(force: true)
    applyHotKeys()
    applyExpansionSettings()

    if !settings.hasCompletedOnboarding || !isAccessibilityGranted {
      showOnboarding()
    }
  }

  // MARK: Panels

  func toggleLauncher() {
    if let panel = launcherPanel, panel.isVisible {
      panel.orderOut(nil)
      return
    }
    viewerPanel?.orderOut(nil)
    refreshApps(force: false)
    let panel = launcherPanel ?? makePanel(model: launcher, preview: nil)
    launcherPanel = panel
    launcher.prepareForPresentation()
    panel.present()
  }

  func toggleSnippetViewer() {
    if let panel = viewerPanel, panel.isVisible {
      panel.orderOut(nil)
      return
    }
    launcherPanel?.orderOut(nil)
    let panel =
      viewerPanel
      ?? makePanel(model: viewer) { [unowned self] result in
        guard case .pasteSnippet(let id) = result.action, let snippet = snippets.snippet(id: id) else { return nil }
        return snippet.isSensitive ? "••••••••" : snippet.content
      }
    viewerPanel = panel
    viewer.prepareForPresentation()
    panel.present()
  }

  private func makePanel(model: SearchModel, preview: ((SearchResult) -> String?)?) -> LauncherPanel {
    var panel: LauncherPanel!
    let view = SearchView(model: model, preview: preview ?? { _ in nil }, onClose: { panel.orderOut(nil) })
    panel = LauncherPanel(rootView: view)
    panel.onResignKey = { [weak panel] in panel?.orderOut(nil) }
    panel.onBecomeKey = { model.requestFocus() }
    return panel
  }

  private func perform(_ result: SearchResult, query: String, from panel: LauncherPanel?) {
    panel?.orderOut(nil)
    usage.record(query: query, id: result.id)
    switch result.action {
    case .open(let url):
      if url.pathExtension == "app" {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
      } else {
        NSWorkspace.shared.open(url)
      }
    case .copy(let text):
      Paster.copy(text)
    case .pasteSnippet(let id):
      guard let snippet = snippets.snippet(id: id) else { return }
      Task {
        // Give focus a moment to return to the app the user was typing in.
        try? await Task.sleep(for: .milliseconds(120))
        await insert(snippet, deleting: 0)
      }
    case .complete:
      break
    }
  }

  // MARK: Snippets

  private func expand(_ match: ExpansionEngine.Match, verify: Bool) {
    Task {
      defer { expansion.finishExpansion() }
      if verify {
        let trigger = snippets.index.entries.first { $0.snippet.id == match.snippet.id }?.trigger ?? ""
        try? await Task.sleep(for: .milliseconds(40))
        guard FocusedText.beforeCaret(length: match.triggerLength) == trigger else { return }
      }
      await insert(match.snippet, deleting: match.triggerLength)
    }
  }

  private func insert(_ snippet: Snippet, deleting: Int) async {
    let template = snippets.content(of: snippet)
    let clipboard = Placeholders.usesClipboard(template) ? (NSPasteboard.general.string(forType: .string) ?? "") : ""
    let rendered = Placeholders.render(template, context: .init(clipboard: clipboard))
    await Paster.insert(
      rendered.text, deletingBackward: deleting, cursorOffsetFromEnd: rendered.cursorOffsetFromEnd,
      concealed: snippet.isSensitive)
  }

  func applyExpansionSettings() {
    expansion.excludedBundleIDs = Set(settings.expansionExcludedApps)
    if settings.autoExpansionEnabled && isAccessibilityGranted {
      expansion.start()
    } else {
      expansion.stop()
    }
  }

  func changeSnippetLocation(_ location: AppSettings.SnippetLocation) {
    settings.snippetLocation = location
    snippets.move(to: settings.snippetDirectory)
  }

  // MARK: Hot keys

  func applyHotKeys() {
    hotKeyConflicts = []
    if !hotKeys.register(settings.launcherHotKey, for: .launcher, handler: { [unowned self] in toggleLauncher() }) {
      hotKeyConflicts.insert(.launcher)
    }
    if !hotKeys.register(settings.snippetViewerHotKey, for: .snippetViewer, handler: { [unowned self] in toggleSnippetViewer() }) {
      hotKeyConflicts.insert(.snippetViewer)
    }
  }

  func setRecordingHotKey(_ recording: Bool) {
    recording ? hotKeys.suspend() : applyHotKeys()
  }

  // MARK: Apps

  private func refreshApps(force: Bool) {
    guard force || Date.now.timeIntervalSince(lastAppScan) > 60 else { return }
    lastAppScan = .now
    let languages = Bundle.main.preferredLocalizations + Locale.preferredLanguages
    let apps = apps
    Task.detached(priority: .utility) {
      apps.entries = AppCatalog.scan(preferredLanguages: languages)
    }
  }

  // MARK: Permissions & windows

  var launchesAtLogin: Bool {
    get { SMAppService.mainApp.status == .enabled }
    set {
      try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
  }

  func requestAccessibility() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    isAccessibilityGranted = AXIsProcessTrustedWithOptions(options)
    pollAccessibility()
  }

  func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    pollAccessibility()
  }

  private func pollAccessibility() {
    permissionPoll?.cancel()
    permissionPoll = Task {
      while !Task.isCancelled && !AXIsProcessTrusted() {
        try? await Task.sleep(for: .seconds(1))
      }
      guard !Task.isCancelled else { return }
      isAccessibilityGranted = true
      applyExpansionSettings()
    }
  }

  func showSettings() {
    let window = settingsWindow ?? makeWindow(title: String(localized: "AetherSeek Settings"), content: SettingsView(controller: self))
    settingsWindow = window
    present(window)
  }

  func showOnboarding() {
    let window = onboardingWindow ?? makeWindow(title: String(localized: "Welcome to AetherSeek"), content: OnboardingView(controller: self))
    onboardingWindow = window
    present(window)
    if !isAccessibilityGranted { pollAccessibility() }
  }

  func finishOnboarding() {
    settings.hasCompletedOnboarding = true
    onboardingWindow?.close()
  }

  private func makeWindow(title: String, content: some View) -> NSWindow {
    let window = NSWindow(contentViewController: NSHostingController(rootView: content))
    window.title = title
    window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.center()
    return window
  }

  private func present(_ window: NSWindow) {
    NSApp.activate()
    // The hosting controller sizes the window on first layout, after `center()` in makeWindow ran.
    if !window.isVisible, let content = window.contentViewController?.view {
      window.setContentSize(content.fittingSize)
      window.center()
    }
    window.makeKeyAndOrderFront(nil)
  }
}
