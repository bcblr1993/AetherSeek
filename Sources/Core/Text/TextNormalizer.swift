import Foundation

/// Canonical form used on both sides of every comparison, so "ＡＢＣ", "abc" and "Àbc"
/// compare equal and katakana matches hiragana.
public enum TextNormalizer {
  public static func normalize(_ text: String) -> String {
    var folded = text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    folded = folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
    return folded.lowercased()
  }

  /// Normalized text with whitespace and common separators removed ("Visual Studio" → "visualstudio").
  public static func compact(_ text: String) -> String {
    String(normalize(text).unicodeScalars.filter { !separators.contains($0) }.map(Character.init))
  }

  static let separators: CharacterSet = .whitespacesAndNewlines
    .union(CharacterSet(charactersIn: "-_.·・'’"))
}

extension Unicode.Scalar {
  var isHan: Bool {
    switch value {
    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF: true
    default: false
    }
  }

  var isKana: Bool {
    switch value {
    case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D: true
    default: false
    }
  }
}

extension String {
  var containsHan: Bool { unicodeScalars.contains(where: \.isHan) }
  var containsKana: Bool { unicodeScalars.contains(where: \.isKana) }
}
