import AetherSeekCore
import Foundation
import Observation

/// User preferences, persisted in UserDefaults. Everything else (snippets, usage) lives in files.
@MainActor @Observable
final class AppSettings {
  enum SnippetLocation: String, CaseIterable, Identifiable {
    case local, iCloud
    var id: String { rawValue }
  }

  private let defaults = UserDefaults.standard

  var launcherHotKey: KeyCombo {
    didSet { store(launcherHotKey, "launcherHotKey") }
  }
  var snippetViewerHotKey: KeyCombo {
    didSet { store(snippetViewerHotKey, "snippetViewerHotKey") }
  }
  var snippetLocation: SnippetLocation {
    didSet { defaults.set(snippetLocation.rawValue, forKey: "snippetLocation") }
  }
  var autoExpansionEnabled: Bool {
    didSet { defaults.set(autoExpansionEnabled, forKey: "autoExpansionEnabled") }
  }
  /// Bundle IDs where typed triggers are never expanded (terminals with their own aliases, games…).
  var expansionExcludedApps: [String] {
    didSet { defaults.set(expansionExcludedApps, forKey: "expansionExcludedApps") }
  }
  var hasCompletedOnboarding: Bool {
    didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
  }

  init() {
    launcherHotKey = Self.load("launcherHotKey") ?? .defaultLauncher
    snippetViewerHotKey = Self.load("snippetViewerHotKey") ?? .defaultSnippetViewer
    snippetLocation =
      SnippetLocation(rawValue: defaults.string(forKey: "snippetLocation") ?? "") ?? .local
    autoExpansionEnabled = defaults.object(forKey: "autoExpansionEnabled") as? Bool ?? true
    expansionExcludedApps = defaults.stringArray(forKey: "expansionExcludedApps") ?? []
    hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
  }

  static var supportDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "AetherSeek")
  }

  static var iCloudDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Mobile Documents/com~apple~CloudDocs/AetherSeek")
  }

  var snippetDirectory: URL {
    switch snippetLocation {
    case .local: Self.supportDirectory.appending(path: "Snippets")
    case .iCloud: Self.iCloudDirectory.appending(path: "Snippets")
    }
  }

  private func store(_ combo: KeyCombo, _ key: String) {
    defaults.set(try? JSONEncoder().encode(combo), forKey: key)
  }

  private static func load(_ key: String) -> KeyCombo? {
    UserDefaults.standard.data(forKey: key).flatMap {
      try? JSONDecoder().decode(KeyCombo.self, from: $0)
    }
  }
}
