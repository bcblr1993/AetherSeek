import AetherSeekCore
import AppKit
import Observation

/// Query → results for one panel. The launcher and the snippet viewer each own one.
@MainActor @Observable
final class SearchModel {
  enum Mode {
    case launcher
    case snippets
  }

  static let maxResults = 9

  let mode: Mode
  var query = "" {
    didSet { if query != oldValue { search() } }
  }
  private(set) var results: [SearchResult] = []
  var selection = 0
  /// Bumped whenever the panel becomes key, so the view can focus the field.
  private(set) var focusRequest = 0

  @ObservationIgnored private let providers: [any ResultProvider]
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored var perform: (SearchResult, String) -> Void = { _, _ in }

  init(mode: Mode, providers: [any ResultProvider]) {
    self.mode = mode
    self.providers = providers
  }

  var selected: SearchResult? {
    results.indices.contains(selection) ? results[selection] : nil
  }

  func prepareForPresentation() {
    query = ""
    selection = 0
    // The viewer lists everything before anything is typed.
    if mode == .snippets { search() } else { results = [] }
  }

  func requestFocus() {
    focusRequest += 1
  }

  func move(_ delta: Int) {
    guard !results.isEmpty else { return }
    selection = (selection + delta + results.count) % results.count
  }

  func activate(_ index: Int? = nil) {
    let index = index ?? selection
    guard results.indices.contains(index) else { return }
    let result = results[index]
    if case .complete(let text) = result.action {
      query = text
      return
    }
    perform(result, query)
  }

  func search() {
    searchTask?.cancel()
    let query = query
    if mode == .launcher && query.trimmingCharacters(in: .whitespaces).isEmpty {
      results = []
      selection = 0
      return
    }
    let providers = providers
    searchTask = Task {
      let found = await withTaskGroup(of: [SearchResult].self) { group in
        for provider in providers {
          group.addTask { await provider.results(for: query) }
        }
        var all: [SearchResult] = []
        for await part in group { all += part }
        return all
      }
      guard !Task.isCancelled else { return }
      let limit = mode == .snippets ? 200 : Self.maxResults
      results = Array(found.sorted { $0.score > $1.score || ($0.score == $1.score && $0.title < $1.title) }.prefix(limit))
      selection = 0
    }
  }
}
