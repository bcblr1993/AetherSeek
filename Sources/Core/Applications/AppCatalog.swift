import Foundation

public struct AppEntry: Sendable, Identifiable {
  public var url: URL
  public var bundleID: String?
  /// Name to show, in the UI language when the bundle has it.
  public var displayName: String
  /// Every name worth matching: file name, English, 简体中文 and 日本語 bundle names.
  public var names: [(String, Phonetics.Language)]
  public var key: SearchKey

  public var id: String { url.path }
}

/// Finds .app bundles in the usual folders and reads their names in every supported language.
public enum AppCatalog {
  public static var defaultRoots: [URL] {
    let fm = FileManager.default
    return [
      URL(filePath: "/Applications"),
      URL(filePath: "/System/Applications"),
      URL(filePath: "/System/Applications/Utilities"),
      URL(filePath: "/System/Library/CoreServices/Applications"),
      URL(filePath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications"),
      fm.homeDirectoryForCurrentUser.appending(path: "Applications"),
    ]
  }

  /// - Parameter preferredLanguages: UI languages in order, used to pick `displayName`.
  public static func scan(roots: [URL] = defaultRoots, preferredLanguages: [String]) -> [AppEntry] {
    var seen = Set<String>()
    var entries: [AppEntry] = []
    for root in roots {
      for url in bundles(in: root, depth: 2) {
        let real = url.resolvingSymlinksInPath().path
        guard seen.insert(real).inserted else { continue }
        entries.append(entry(for: url, preferredLanguages: preferredLanguages))
      }
    }
    return entries
  }

  static func bundles(in root: URL, depth: Int) -> [URL] {
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]))
      ?? []
    var found: [URL] = []
    for url in contents {
      if url.pathExtension == "app" {
        found.append(url)
      } else if depth > 1,
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      {
        found += bundles(in: url, depth: depth - 1)
      }
    }
    return found
  }

  public static func entry(for url: URL, preferredLanguages: [String]) -> AppEntry {
    let fileName = url.deletingPathExtension().lastPathComponent
    let bundle = Bundle(url: url)
    let info = bundle?.infoDictionary ?? [:]
    let baseName = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)

    let localized = bundle.map(localizedNames) ?? [:]
    var names: [(String, Phonetics.Language)] = [(fileName, .unknown)]
    if let baseName { names.append((baseName, .unknown)) }
    for (language, name) in localized.sorted(by: { $0.key < $1.key }) {
      let hint: Phonetics.Language =
        language.hasPrefix("zh") ? .chinese : language.hasPrefix("ja") ? .japanese : .unknown
      names.append((name, hint))
    }
    var unique: [(String, Phonetics.Language)] = []
    for name in names where !unique.contains(where: { $0.0 == name.0 }) { unique.append(name) }

    let display =
      preferredLanguages.lazy.compactMap { language in
        localized.first(where: { Self.matches(language, $0.key) })?.value
      }.first ?? fileName

    return AppEntry(
      url: url, bundleID: bundle?.bundleIdentifier, displayName: display, names: unique,
      key: SearchKey(names: unique))
  }

  /// Language code → display name, from `InfoPlist.strings` per lproj or `InfoPlist.loctable`.
  static func localizedNames(_ bundle: Bundle) -> [String: String] {
    var names: [String: String] = [:]
    guard let resources = bundle.resourceURL else { return names }
    if let table = NSDictionary(contentsOf: resources.appending(path: "InfoPlist.loctable"))
      as? [String: [String: Any]]
    {
      for (language, strings) in table where isSupported(language) {
        if let name = (strings["CFBundleDisplayName"] ?? strings["CFBundleName"]) as? String {
          names[canonical(language)] = name
        }
      }
    }
    for lproj in lprojNames {
      let url = resources.appending(path: "\(lproj).lproj/InfoPlist.strings")
      guard let strings = NSDictionary(contentsOf: url) as? [String: Any],
        let name = (strings["CFBundleDisplayName"] ?? strings["CFBundleName"]) as? String
      else { continue }
      names[canonical(lproj), default: name] = name
    }
    return names
  }

  static let lprojNames = [
    "en", "English", "Base", "zh-Hans", "zh_CN", "zh-CN", "zh", "ja", "Japanese",
  ]

  static func isSupported(_ language: String) -> Bool {
    let code = canonical(language)
    return code == "en" || code == "zh-Hans" || code == "ja"
  }

  static func canonical(_ language: String) -> String {
    switch language {
    case "English", "Base", "en": "en"
    case "Japanese", "ja": "ja"
    case "zh-Hans", "zh_CN", "zh-CN", "zh", "zh_Hans": "zh-Hans"
    default: language
    }
  }

  /// "zh-Hans-CN" matches "zh-Hans"; "en-US" matches "en".
  static func matches(_ preferred: String, _ available: String) -> Bool {
    preferred == available || preferred.hasPrefix(available + "-")
  }
}
