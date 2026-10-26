import Foundation
import Testing

@testable import AetherSeekCore

struct ExpansionEngineTests {
  let phone = Snippet(name: "Phone", keyword: "phone", content: "123")
  let id = Snippet(name: "ID", keyword: "id", content: "A")
  let zid = Snippet(name: "ZID", keyword: "zid", content: "B")

  @Test func expandsWhenTriggerCompletes() {
    var engine = ExpansionEngine(triggers: [":phone": phone])
    for character in ":phon" { #expect(engine.type(String(character)) == nil) }
    #expect(engine.type("e") == .init(snippet: phone, triggerLength: 6))
    // The buffer starts over after an expansion.
    #expect(engine.type("e") == nil)
  }

  @Test func prefersLongestTrigger() {
    var engine = ExpansionEngine(triggers: ["id": id, "zid": zid])
    _ = engine.type("z")
    _ = engine.type("i")
    #expect(engine.type("d")?.snippet == zid)
  }

  @Test func backspaceAndReset() {
    var engine = ExpansionEngine(triggers: [":id": id])
    _ = engine.type(":")
    _ = engine.type("x")
    engine.deleteBackward()
    _ = engine.type("i")
    #expect(engine.type("d")?.snippet == id)
    _ = engine.type(":")
    _ = engine.type("i")
    engine.reset()
    #expect(engine.type("d") == nil)
  }

  @Test func newlineBreaksTrigger() {
    var engine = ExpansionEngine(triggers: [":id": id])
    _ = engine.type(":")
    _ = engine.type("\r")
    _ = engine.type("i")
    #expect(engine.type("d") == nil)
  }

  @Test func emptyEngineIgnoresInput() {
    var engine = ExpansionEngine()
    #expect(engine.type("a") == nil)
  }
}

struct SnippetIndexTests {
  @Test func triggersIncludeGroupAffixesAndSkipDisabled() {
    let snippet = Snippet(name: "Phone", keyword: "phone", content: "1")
    let off = Snippet(name: "Off", keyword: "off", content: "2")
    let manual = Snippet(name: "Manual", keyword: "man", content: "3", autoExpands: false)
    let index = SnippetIndex(groups: [
      SnippetGroup(name: "A", prefix: ":", snippets: [snippet, manual]),
      SnippetGroup(name: "B", isEnabled: false, snippets: [off]),
    ])
    #expect(index.expandable == [":phone": snippet])
    #expect(index.entries.count == 2)
  }

  @Test func reportsProblems() {
    let a = Snippet(name: "a", keyword: "id", content: "")
    let b = Snippet(name: "b", keyword: "id", content: "")
    let c = Snippet(name: "c", keyword: "idea", content: "")
    let problems = SnippetIndex(groups: [SnippetGroup(name: "G", snippets: [a, b, c])]).problems
    #expect(problems.contains(.duplicate("id", [a.id, b.id])))
    #expect(problems.contains(.shadowed(short: "id", long: "idea", c.id)))
  }
}

struct PlaceholderTests {
  let context = Placeholders.Context(
    clipboard: "CLIP", now: Date(timeIntervalSince1970: 0), locale: Locale(identifier: "en_US"),
    timeZone: TimeZone(identifier: "UTC")!)

  @Test func fillsTokens() {
    let rendered = Placeholders.render("a {clipboard} {isodate:yyyy-MM-dd} {date:short}", context: context)
    #expect(rendered.text == "a CLIP 1970-01-01 1/1/70")
    #expect(rendered.cursorOffsetFromEnd == 0)
  }

  @Test func cursorOffset() {
    let rendered = Placeholders.render("<b>{cursor}</b>", context: context)
    #expect(rendered.text == "<b></b>")
    #expect(rendered.cursorOffsetFromEnd == 4)
  }

  @Test func leavesUnknownAndBracesAlone() {
    #expect(Placeholders.render(#"{"a":1} {nope} {"#, context: context).text == #"{"a":1} {nope} {"#)
  }
}

struct SnippetStoreTests {
  func makeStore() -> SnippetStore {
    SnippetStore(
      directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
      secrets: InMemorySecretStore())
  }

  @Test func roundTripsAndHidesSecrets() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let secret = Snippet(name: "pwd", keyword: "pwd", content: "hunter2", isSensitive: true)
    let plain = Snippet(name: "hi", keyword: "hi", content: "hello")
    let group = SnippetGroup(name: "G", prefix: ":", snippets: [secret, plain])
    try store.save(group)

    let raw = try String(contentsOf: store.url(for: group.id), encoding: .utf8)
    #expect(!raw.contains("hunter2"))
    let loaded = try store.load()
    #expect(loaded.count == 1)
    #expect(loaded[0].snippets[0].content == "")
    #expect(store.content(of: loaded[0].snippets[0]) == "hunter2")
    #expect(store.content(of: loaded[0].snippets[1]) == "hello")

    try store.delete(loaded[0])
    #expect(try store.load().isEmpty)
    #expect(store.secrets.read(secret.id) == nil)
  }

  @Test func skipsBrokenFiles() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    try store.save(SnippetGroup(name: "ok"))
    try Data("{".utf8).write(to: store.directory.appending(path: "bad.json"))
    #expect(try store.load().map(\.name) == ["ok"])
  }
}

struct AlfredImporterTests {
  @Test func importsGroupsAndAffixes() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appending(path: "snippets/常用")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let info: NSDictionary = ["snippetkeywordprefix": ":", "snippetkeywordsuffix": ""]
    info.write(to: folder.appending(path: "info.plist"), atomically: true)
    let json = #"{"alfredsnippet":{"snippet":"138{cursor}","uid":"X","name":"手机","keyword":"phone","dontautoexpand":true}}"#
    try Data(json.utf8).write(to: folder.appending(path: "手机 [X].json"))

    let groups = try AlfredSnippetImporter.load(from: root)
    #expect(groups.count == 1)
    #expect(groups[0].name == "常用")
    #expect(groups[0].prefix == ":")
    #expect(groups[0].isEnabled)
    let snippet = try #require(groups[0].snippets.first)
    #expect(snippet.keyword == "phone")
    #expect(snippet.content == "138{cursor}")
    #expect(!snippet.autoExpands)
  }

  @Test func snippetProviderNeedsKeywordInLauncher() async {
    let snippet = Snippet(name: "Phone", keyword: "phone", content: "123")
    let launcher = SnippetProvider(requiresKeyword: true)
    let viewer = SnippetProvider(requiresKeyword: false)
    let index = SnippetIndex(groups: [SnippetGroup(name: "G", prefix: ":", snippets: [snippet])])
    launcher.index = index
    viewer.index = index
    #expect(await launcher.results(for: "phone").isEmpty)
    #expect(await launcher.results(for: "snip ph").count == 1)
    #expect(await viewer.results(for: "").count == 1)
    #expect(await viewer.results(for: "123").count == 1)
  }
}
