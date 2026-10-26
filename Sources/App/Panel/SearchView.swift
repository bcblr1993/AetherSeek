import AetherSeekCore
import AppKit
import SwiftUI

struct SearchView: View {
  @Bindable var model: SearchModel
  /// Snippet viewer only: the text the selected row would insert.
  var preview: (SearchResult) -> String? = { _ in nil }
  var onClose: () -> Void

  @FocusState private var fieldFocused: Bool

  var body: some View {
    GlassEffectContainer {
      VStack(spacing: 0) {
        field
        if !model.results.isEmpty {
          Divider().padding(.horizontal, 12)
          if model.mode == .snippets {
            HStack(alignment: .top, spacing: 0) {
              list.frame(width: 300)
              Divider()
              snippetPreview
            }
            .frame(height: 360)
          } else {
            list
          }
        }
      }
      .frame(width: model.mode == .snippets ? 760 : 680)
      .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
    .padding(20)
    .onKeyPress(.downArrow) { model.move(1); return .handled }
    .onKeyPress(.upArrow) { model.move(-1); return .handled }
    .onKeyPress(.escape) { onClose(); return .handled }
    .onKeyPress(phases: .down) { press in
      guard press.modifiers == .command, let digit = Int(press.characters), (1...9).contains(digit)
      else { return .ignored }
      model.activate(digit - 1)
      return .handled
    }
    .onChange(of: model.focusRequest, initial: true) { fieldFocused = true }
  }

  private var field: some View {
    HStack(spacing: 12) {
      Image(systemName: model.mode == .snippets ? "text.quote" : "magnifyingglass")
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.secondary)
      TextField(
        model.mode == .snippets ? String(localized: "Search snippets") : String(localized: "AetherSeek"),
        text: $model.query
      )
      .textFieldStyle(.plain)
      .font(.system(size: 26, weight: .regular))
      .focused($fieldFocused)
      .onSubmit { model.activate() }
    }
    .padding(.horizontal, 20)
    .frame(height: 64)
  }

  private var list: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
            ResultRow(result: result, index: index, isSelected: index == model.selection, compact: model.mode == .snippets)
              .contentShape(.rect)
              .onTapGesture { model.activate(index) }
          }
        }
        .padding(8)
      }
      .scrollIndicators(.never)
      .frame(maxHeight: model.mode == .snippets ? .infinity : CGFloat(SearchModel.maxResults) * 52 + 16)
      .fixedSize(horizontal: false, vertical: model.mode == .launcher)
      .onChange(of: model.selection) {
        if let id = model.selected?.id { proxy.scrollTo(id) }
      }
    }
  }

  private var snippetPreview: some View {
    ScrollView {
      Text(model.selected.flatMap(preview) ?? "")
        .font(.system(size: 13, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
    }
  }
}

struct ResultRow: View {
  let result: SearchResult
  let index: Int
  let isSelected: Bool
  var compact = false

  var body: some View {
    HStack(spacing: 12) {
      ResultIcon(icon: result.icon)
        .frame(width: compact ? 22 : 34, height: compact ? 22 : 34)
      VStack(alignment: .leading, spacing: 2) {
        Text(result.title)
          .font(.system(size: compact ? 13 : 16, weight: .medium))
          .lineLimit(1)
        if !result.subtitle.isEmpty {
          Text(result.subtitle)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      Spacer(minLength: 8)
      if !compact && index < 9 {
        Text(verbatim: "⌘\(index + 1)")
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: compact ? 40 : 50)
    .background {
      if isSelected {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.22))
      }
    }
  }
}

struct ResultIcon: View {
  let icon: SearchResult.Icon

  var body: some View {
    switch icon {
    case .file(let url):
      Image(nsImage: IconCache.shared.icon(for: url)).resizable().interpolation(.high)
    case .symbol(let name):
      Image(systemName: name)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }
}

@MainActor
final class IconCache {
  static let shared = IconCache()
  private let cache = NSCache<NSURL, NSImage>()

  func icon(for url: URL) -> NSImage {
    if let image = cache.object(forKey: url as NSURL) { return image }
    let image = NSWorkspace.shared.icon(forFile: url.path)
    cache.setObject(image, forKey: url as NSURL)
    return image
  }
}
