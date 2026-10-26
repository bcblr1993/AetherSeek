import Foundation
import Testing

@testable import AetherSeekCore

struct TextTests {
  @Test func normalizesWidthCaseAndKana() {
    #expect(TextNormalizer.normalize("ＡＢＣ") == "abc")
    #expect(TextNormalizer.normalize("Àbc") == "abc")
    #expect(TextNormalizer.normalize("めも") == TextNormalizer.normalize("メモ"))
    #expect(TextNormalizer.compact("Visual Studio-Code") == "visualstudiocode")
  }

  @Test func chineseReadings() {
    let reading = Phonetics.readings(of: "微信", language: .chinese)
    #expect(reading.contains(Phonetics.Reading(full: "weixin", initials: "wx")))
    #expect(Phonetics.readings(of: "系统设置", language: .chinese).first?.initials == "xtsz")
  }

  @Test func japaneseReadings() {
    let reading = Phonetics.readings(of: "システム設定", language: .japanese)
    #expect(reading.first?.full == "shisutemusettei")
    #expect(reading.first?.initials == "ss")
  }

  @Test func latinTextHasNoReadings() {
    #expect(Phonetics.readings(of: "Safari").isEmpty)
  }
}

struct MatcherTests {
  @Test func splitsWords() {
    #expect(SearchKey.split("PyCharm CE") == ["py", "charm", "ce"])
    #expect(SearchKey.split("Visual Studio Code") == ["visual", "studio", "code"])
  }

  @Test func ranksExactOverPrefixOverFuzzy() throws {
    let key = SearchKey("Safari")
    let exact = try #require(Matcher.score("safari", key))
    let prefix = try #require(Matcher.score("saf", key))
    let fuzzy = try #require(Matcher.score("sfr", key))
    #expect(exact > prefix)
    #expect(prefix > fuzzy)
    #expect(Matcher.score("xyz", key) == nil)
  }

  @Test func matchesInitialsAndWordStarts() {
    let key = SearchKey("Visual Studio Code")
    #expect(Matcher.score("vsc", key) != nil)
    #expect(Matcher.score("code", key) != nil)
  }

  @Test func matchesPinyinAndRomaji() {
    let wechat = SearchKey(names: [("WeChat", .unknown), ("微信", .chinese)])
    #expect(Matcher.score("wx", wechat) != nil)
    #expect(Matcher.score("weixin", wechat) != nil)
    #expect(Matcher.score("微信", wechat) != nil)
    let settings = SearchKey(names: [("システム設定", .japanese)])
    #expect(Matcher.score("shisutemu", settings) != nil)
    #expect(Matcher.score("しすてむ", settings) != nil)
  }

  @Test func singleLetterDoesNotFuzzyMatch() {
    #expect(Matcher.score("q", SearchKey("Safari")) == nil)
  }

  @Test func keywordArgument() {
    #expect(argument(of: "tr hello world", keyword: "tr") == "hello world")
    #expect(argument(of: "TR  hi", keyword: "tr") == "hi")
    #expect(argument(of: "tr", keyword: "tr") == nil)
    #expect(argument(of: "trello", keyword: "tr") == nil)
  }
}

struct UsageTests {
  @Test func learnsChoices() {
    let usage = UsageStore(url: nil)
    #expect(usage.boost(query: "ch", id: "a") == 0)
    usage.record(query: "ch", id: "a")
    #expect(usage.boost(query: "ch", id: "a") > 500)
    #expect(usage.boost(query: "x", id: "a") > 0)
    #expect(usage.boost(query: "ch", id: "b") == 0)
  }

  @Test func persists() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }
    UsageStore(url: url).record(query: "s", id: "safari")
    #expect(UsageStore(url: url).boost(query: "s", id: "safari") > 500)
  }
}

struct AppCatalogTests {
  @Test func readsLocalizedNamesOfSystemApps() throws {
    let entries = AppCatalog.scan(preferredLanguages: ["zh-Hans-CN"])
    let settings = try #require(entries.first { $0.bundleID == "com.apple.systempreferences" })
    #expect(settings.names.contains { $0.0 == "系统设置" })
    #expect(settings.displayName == "系统设置")
    #expect(Matcher.score("xtsz", settings.key) != nil)
  }

  @Test func providerUsesUsage() async {
    let usage = UsageStore(url: nil)
    let provider = AppProvider(usage: usage)
    provider.entries = [
      AppCatalog.entry(for: URL(filePath: "/Applications/Chess.app"), preferredLanguages: ["en"]),
      AppCatalog.entry(for: URL(filePath: "/Applications/Chrome.app"), preferredLanguages: ["en"]),
    ]
    usage.record(query: "ch", id: "app:/Applications/Chrome.app")
    let results = await provider.results(for: "ch").sorted { $0.score > $1.score }
    #expect(results.first?.title == "Chrome")
  }

  @Test func languageMatching() {
    #expect(AppCatalog.matches("zh-Hans-CN", "zh-Hans"))
    #expect(AppCatalog.matches("en", "en"))
    #expect(!AppCatalog.matches("zh-Hant", "zh-Hans"))
  }
}

struct KeyComboTests {
  @Test func display() {
    #expect(KeyCombo.defaultLauncher.displayString == "⌥Space")
    #expect(KeyCombo.defaultSnippetViewer.displayString == "⌃⌥⌘V")
  }

  @Test func validity() {
    #expect(!KeyCombo(keyCode: 0, modifiers: []).isValid)
    #expect(KeyCombo(keyCode: 122, modifiers: []).isValid)
  }

  @Test func codable() throws {
    let data = try JSONEncoder().encode(KeyCombo.defaultSnippetViewer)
    #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == .defaultSnippetViewer)
  }
}
