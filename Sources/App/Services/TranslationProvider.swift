import AetherSeekCore
import Foundation
import NaturalLanguage
import Translation

/// `tr <text>`: on-device translation with Apple's Translation framework. Text in the UI
/// language goes to English, anything else goes to the UI language.
final class TranslationProvider: ResultProvider {
  static let keyword = "tr"
  /// System Settings › General › Language & Region, where translation languages are downloaded.
  static let languageSettings = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!

  func results(for query: String) async -> [SearchResult] {
    guard let text = argument(of: query, keyword: Self.keyword) else { return [] }
    guard !text.isEmpty else {
      return [row(id: "hint", title: String(localized: "Type text to translate"), subtitle: "", action: .complete("tr "))]
    }
    // Typing fast fires a search per key; only translate once the user pauses.
    try? await Task.sleep(for: .milliseconds(250))
    guard !Task.isCancelled else { return [] }

    let source = Self.detect(text)
    let target = Self.target(for: source)
    guard let source else {
      return [row(id: "unknown", title: String(localized: "Couldn’t detect the language"), subtitle: text, action: .copy(text))]
    }
    let status = await LanguageAvailability().status(from: source, to: target)
    switch status {
    case .installed:
      do {
        let session = TranslationSession(installedSource: source, target: target)
        let response = try await session.translate(text)
        let name = Locale.current.localizedString(forLanguageCode: target.languageCode?.identifier ?? "") ?? ""
        return [
          row(
            id: "result", title: response.targetText,
            subtitle: String(localized: "\(name) · ⏎ to copy"), action: .copy(response.targetText))
        ]
      } catch {
        guard !Task.isCancelled else { return [] }
        return [row(id: "error", title: String(localized: "Translation failed"), subtitle: error.localizedDescription, action: .copy(text))]
      }
    case .supported:
      return [
        row(
          id: "download", title: String(localized: "Download translation languages to translate offline"),
          subtitle: String(localized: "Opens Language & Region settings"), action: .open(Self.languageSettings))
      ]
    default:
      return [row(id: "unsupported", title: String(localized: "This language pair isn’t supported"), subtitle: text, action: .copy(text))]
    }
  }

  private func row(id: String, title: String, subtitle: String, action: SearchResult.Action) -> SearchResult {
    // Fixed high score: once "tr " is typed, translation is the only thing the user wants.
    SearchResult(id: "translate:" + id, title: title, subtitle: subtitle, icon: .symbol("translate"), action: action, score: 5000)
  }

  static func detect(_ text: String) -> Locale.Language? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage else { return nil }
    return Locale.Language(identifier: language.rawValue)
  }

  static func target(for source: Locale.Language?) -> Locale.Language {
    let preferred = Locale.preferredLanguages.first.map(Locale.Language.init(identifier:)) ?? Locale.Language(identifier: "en")
    let english = Locale.Language(identifier: "en")
    guard let source else { return preferred }
    return source.languageCode == preferred.languageCode ? (preferred.languageCode == english.languageCode ? Locale.Language(identifier: "zh-Hans") : english) : preferred
  }
}
