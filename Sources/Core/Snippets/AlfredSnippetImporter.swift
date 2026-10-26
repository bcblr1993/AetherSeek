import Foundation

/// One-time import of Alfred's `Alfred.alfredpreferences/snippets` folder. Data only:
/// Alfred's placeholder syntax is close enough that content is copied as-is.
public enum AlfredSnippetImporter {
  public static var defaultPreferences: URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Mobile Documents/com~apple~CloudDocs/Alfred/Alfred.alfredpreferences")
  }

  /// - Parameter preferences: the `.alfredpreferences` bundle or its `snippets` folder.
  public static func load(from preferences: URL) throws -> [SnippetGroup] {
    var root = preferences
    if root.lastPathComponent != "snippets" { root = root.appending(path: "snippets") }
    let folders = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    var groups: [SnippetGroup] = []
    for folder in folders
    where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
      var group = SnippetGroup(name: folder.lastPathComponent)
      if let info = NSDictionary(contentsOf: folder.appending(path: "info.plist")) {
        group.prefix = info["snippetkeywordprefix"] as? String ?? ""
        group.suffix = info["snippetkeywordsuffix"] as? String ?? ""
        group.isEnabled = !(info["disabled"] as? Bool ?? false)
      }
      let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
      for file in files where file.pathExtension == "json" {
        guard let data = try? Data(contentsOf: file),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let raw = object["alfredsnippet"] as? [String: Any]
        else { continue }
        group.snippets.append(
          Snippet(
            name: raw["name"] as? String ?? "",
            keyword: raw["keyword"] as? String ?? "",
            content: raw["snippet"] as? String ?? "",
            autoExpands: !(raw["dontautoexpand"] as? Bool ?? false)))
      }
      group.snippets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      groups.append(group)
    }
    return groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}
