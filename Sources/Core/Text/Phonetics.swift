import Foundation

/// Latin readings of CJK names, so "wx" / "weixin" find 微信 and "shashin" finds 写真.
public enum Phonetics {
  /// Script hint for a name. Han-only text is ambiguous (中文 vs 日本語 kanji), so callers
  /// that know where a name came from (e.g. a `ja.lproj` bundle name) pass it along.
  public enum Language: String, Sendable, Codable {
    case chinese, japanese, unknown
  }

  public struct Reading: Equatable, Sendable {
    /// Readings joined without spaces: "weixin", "shisutemusettei".
    public var full: String
    /// First letter of every syllable (Chinese) or word (Japanese): "wx", "ss".
    public var initials: String
  }

  public static func readings(of text: String, language: Language = .unknown) -> [Reading] {
    guard text.containsHan || text.containsKana else { return [] }
    var result: [Reading] = []
    if text.containsKana || language == .japanese {
      if let reading = japanese(text) { result.append(reading) }
    }
    if text.containsHan && !text.containsKana && language != .japanese {
      if let reading = chinese(text) { result.append(reading) }
    }
    if text.containsHan && !text.containsKana && language == .unknown {
      if let reading = japanese(text), !result.contains(reading) { result.append(reading) }
    }
    return result
  }

  static func chinese(_ text: String) -> Reading? {
    // The tokenizer resolves polyphones per word (重庆 → chongqing); the per-character
    // transform is the only way to get syllable boundaries for initials.
    let full = tokenize(text, locale: "zh-Hans").joined()
    var initials = ""
    for character in text {
      let piece = String(character)
      if piece.containsHan,
        let latin = piece.applyingTransform(.mandarinToLatin, reverse: false)
      {
        initials += latin.prefix(1)
      } else if let first = TextNormalizer.compact(piece).first {
        initials.append(first)
      }
    }
    return make(full: full, initials: initials)
  }

  static func japanese(_ text: String) -> Reading? {
    let words = tokenize(text, locale: "ja")
    return make(full: words.joined(), initials: String(words.compactMap(\.first)))
  }

  private static func make(full: String, initials: String) -> Reading? {
    let full = TextNormalizer.compact(full)
    guard !full.isEmpty else { return nil }
    return Reading(full: full, initials: TextNormalizer.compact(initials))
  }

  private static func tokenize(_ text: String, locale: String) -> [String] {
    let range = CFRange(location: 0, length: (text as NSString).length)
    let tokenizer = CFStringTokenizerCreate(
      nil, text as CFString, range, kCFStringTokenizerUnitWord, Locale(identifier: locale) as CFLocale)
    var words: [String] = []
    while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
      let attribute = CFStringTokenizerCopyCurrentTokenAttribute(
        tokenizer, kCFStringTokenizerAttributeLatinTranscription)
      if let latin = attribute as? String {
        words.append(TextNormalizer.compact(latin))
      }
    }
    return words.filter { !$0.isEmpty }
  }
}
