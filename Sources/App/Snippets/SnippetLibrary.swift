import AetherSeekCore
import Foundation
import Observation

/// The live snippet collection: loads from the chosen folder, saves edits, reloads when a
/// synced folder changes underneath us, and keeps providers and the expander up to date.
@MainActor @Observable
final class SnippetLibrary {
  private(set) var groups: [SnippetGroup] = []
  private(set) var lastError: String?

  @ObservationIgnored private(set) var store: SnippetStore
  @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
  @ObservationIgnored private var reloadTask: Task<Void, Never>?
  @ObservationIgnored var onChange: (SnippetIndex) -> Void = { _ in }

  let secrets: any SecretStore

  init(directory: URL, secrets: any SecretStore = KeychainSecretStore()) {
    self.secrets = secrets
    store = SnippetStore(directory: directory, secrets: secrets)
  }

  var index: SnippetIndex { SnippetIndex(groups: groups) }

  func reload() {
    do {
      groups = try store.load()
      lastError = nil
      Log.snippets.info("Loaded \(self.groups.count) groups from \(self.store.directory.path, privacy: .public)")
    } catch {
      lastError = error.localizedDescription
    }
    onChange(index)
    watch()
  }

  func snippet(id: UUID) -> Snippet? {
    groups.lazy.flatMap(\.snippets).first { $0.id == id }
  }

  func content(of snippet: Snippet) -> String {
    store.content(of: snippet)
  }

  func save(_ group: SnippetGroup) {
    var group = group
    let previous = groups.first { $0.id == group.id }
    for index in group.snippets.indices {
      let snippet = group.snippets[index]
      let wasSensitive = previous?.snippets.first { $0.id == snippet.id }?.isSensitive ?? false
      // Turning sensitivity off brings the secret back into the JSON file.
      if wasSensitive && !snippet.isSensitive {
        if snippet.content.isEmpty { group.snippets[index].content = secrets.read(snippet.id) ?? "" }
        secrets.delete(snippet.id)
      }
    }
    for removed in previous?.snippets ?? [] where removed.isSensitive && !group.snippets.contains(where: { $0.id == removed.id }) {
      secrets.delete(removed.id)
    }
    perform { try store.save(group) }
  }

  func delete(_ group: SnippetGroup) {
    perform { try store.delete(group) }
  }

  /// Adds Alfred's groups as new groups; existing ones are left alone.
  func importAlfred(from url: URL) -> Int {
    do {
      let imported = try AlfredSnippetImporter.load(from: url)
      for group in imported { try store.save(group) }
      reload()
      return imported.reduce(0) { $0 + $1.snippets.count }
    } catch {
      lastError = error.localizedDescription
      return 0
    }
  }

  /// Switches folders, copying the current groups over when the destination has none.
  func move(to directory: URL) {
    let old = store
    store = SnippetStore(directory: directory, secrets: secrets)
    if (try? store.load())?.isEmpty ?? true {
      for group in (try? old.load()) ?? [] { try? store.save(group) }
    }
    reload()
  }

  private func perform(_ change: () throws -> Void) {
    do {
      try change()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
    reload()
  }

  private func watch() {
    watcher?.cancel()
    try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
    let descriptor = open(store.directory.path, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.scheduleReload() }
    }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    watcher = source
  }

  /// Our own saves trigger the watcher too; coalesce bursts (and iCloud's multi-step writes).
  private func scheduleReload() {
    reloadTask?.cancel()
    reloadTask = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      let fresh = (try? store.load()) ?? groups
      if fresh != groups {
        groups = fresh
        onChange(index)
      }
    }
  }
}
