import AetherSeekCore
import SwiftUI

/// Edits one group on a local draft and saves shortly after the user stops typing.
struct SnippetGroupEditor: View {
  let library: SnippetLibrary
  @State private var draft: SnippetGroup
  @State private var selectedSnippet: UUID?
  @State private var saveTask: Task<Void, Never>?

  init(library: SnippetLibrary, group: SnippetGroup) {
    self.library = library
    _draft = State(initialValue: group)
    _selectedSnippet = State(initialValue: group.snippets.first?.id)
  }

  var body: some View {
    VStack(spacing: 0) {
      groupHeader
      problemsBanner
      Divider()
      HSplitView {
        snippetList.frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
        Group {
          if let index = draft.snippets.firstIndex(where: { $0.id == selectedSnippet }) {
            SnippetForm(snippet: $draft.snippets[index], trigger: draft.trigger(for: draft.snippets[index]), library: library)
              .id(draft.snippets[index].id)
          } else {
            ContentUnavailableView("No Snippet Selected", systemImage: "text.cursor")
          }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onChange(of: draft) { scheduleSave() }
    .onDisappear { saveNow() }
  }

  private var groupHeader: some View {
    HStack(spacing: 12) {
      TextField("Group name", text: $draft.name)
        .textFieldStyle(.roundedBorder)
      LabeledContent("Prefix") {
        TextField(text: $draft.prefix) { EmptyView() }.textFieldStyle(.roundedBorder).monospaced().frame(width: 60)
      }
      LabeledContent("Suffix") {
        TextField(text: $draft.suffix) { EmptyView() }.textFieldStyle(.roundedBorder).monospaced().frame(width: 60)
      }
      Toggle("Enabled", isOn: $draft.isEnabled)
    }
    .padding(12)
  }

  @ViewBuilder private var problemsBanner: some View {
    let ids = Set(draft.snippets.map(\.id))
    let problems = library.index.problems.compactMap { problem -> String? in
      switch problem {
      case .duplicate(let trigger, let owners) where !ids.isDisjoint(with: owners):
        String(localized: "“\(trigger)” is used by more than one snippet.")
      case .shadowed(let short, let long, let owner) where ids.contains(owner):
        String(localized: "“\(long)” can never expand because “\(short)” fires first.")
      default:
        nil
      }
    }
    if !problems.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill") }
      }
      .font(.caption)
      .foregroundStyle(.orange)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.bottom, 8)
    }
  }

  private var snippetList: some View {
    List(selection: $selectedSnippet) {
      ForEach(draft.snippets) { snippet in
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            if snippet.isSensitive { Image(systemName: "lock.fill").font(.caption2) }
            Text(snippet.name.isEmpty ? String(localized: "Untitled") : snippet.name)
          }
          Text(draft.trigger(for: snippet) ?? "—").font(.caption).monospaced().foregroundStyle(.secondary)
        }
        .tag(snippet.id)
      }
    }
    .safeAreaInset(edge: .bottom) {
      HStack {
        Button {
          let snippet = Snippet(name: String(localized: "New Snippet"), keyword: "", content: "")
          draft.snippets.append(snippet)
          selectedSnippet = snippet.id
        } label: { Image(systemName: "plus") }
        Button {
          guard let id = selectedSnippet, let index = draft.snippets.firstIndex(where: { $0.id == id }) else { return }
          draft.snippets.remove(at: index)
          selectedSnippet = draft.snippets.indices.contains(index) ? draft.snippets[index].id : draft.snippets.last?.id
        } label: { Image(systemName: "minus") }
        .disabled(selectedSnippet == nil)
        Spacer()
      }
      .buttonStyle(.borderless)
      .padding(8)
    }
  }

  private func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(for: .milliseconds(600))
      guard !Task.isCancelled else { return }
      library.save(draft)
    }
  }

  private func saveNow() {
    guard saveTask != nil else { return }
    saveTask?.cancel()
    saveTask = nil
    library.save(draft)
  }
}

struct SnippetForm: View {
  @Binding var snippet: Snippet
  let trigger: String?
  let library: SnippetLibrary
  @State private var revealed = false

  var body: some View {
    Form {
      TextField("Name", text: $snippet.name)
      TextField("Keyword", text: $snippet.keyword).monospaced()
      LabeledContent("Trigger", value: trigger ?? "—").monospaced()
      Toggle("Expand automatically", isOn: $snippet.autoExpands)
      Toggle(isOn: $snippet.isSensitive) {
        Text("Sensitive (store in Keychain)")
        Text("Kept in this Mac’s Keychain and not synced through iCloud Drive.")
      }
      Section {
        if snippet.isSensitive && !revealed {
          Button("Show content") {
            // Sensitive drafts hold no text until the user asks for it.
            if snippet.content.isEmpty { snippet.content = library.content(of: snippet) }
            revealed = true
          }
        } else {
          TextEditor(text: $snippet.content)
            .font(.system(size: 13, design: .monospaced))
            .frame(minHeight: 180)
        }
      } header: {
        Text("Content")
      } footer: {
        Text("Placeholders: {clipboard} {date} {time} {datetime} {isodate:yyyy-MM-dd} {uuid} {cursor}")
          .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
    }
    .formStyle(.grouped)
  }
}
