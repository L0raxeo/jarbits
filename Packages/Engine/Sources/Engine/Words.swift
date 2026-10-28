import Foundation

/// The one tokenizer the stores key by: lowercased words with accents gone.
/// Apostrophes vanish ("macy's" → "macys"); every other non-letter splits
/// words, periods included, so "zillow.com" is "zillow" + "com". No list
/// of words lives here: this only splits, it never decides.
public enum Words {
    public static func split(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var words: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if scalar == "'" || scalar == "\u{2019}" {
                continue
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// The words joined by single spaces: what two spellings of one thing share.
    public static func key(_ text: String) -> String {
        split(text).joined(separator: " ")
    }
}
