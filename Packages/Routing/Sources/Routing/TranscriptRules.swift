import Foundation

/// What can be done to a spoken transcript without a model: the fillers
/// out, a self-correction noticed, and a check that a model's rewrite used
/// only words that were said. The correction itself is left to the model:
/// how far back "no wait tokyo" reaches is a judgement, not a rule.
public enum TranscriptRules {
    /// Sounds, never words: safe to drop wherever they stand.
    public static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "er", "erm", "hmm", "hm", "mm", "mhm"]

    /// Only fillers at the very start; "so" and "well" mean something later on.
    public static let openers: [String] = ["okay so", "ok so", "okay", "ok", "so", "well"]

    /// The speaker changed their mind: the model should look at this one.
    public static let correctionCues: [String] = [
        "no wait", "wait no", "i mean", "i meant", "actually", "scratch that", "sorry", "no not",
    ]

    /// Lowercased words with punctuation stripped; apostrophes stay ("what's").
    public static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { word in
                String(word.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "'" })
            }
            .filter { !$0.isEmpty }
    }

    /// `text` without standalone fillers, and without an opener at the start.
    /// Punctuation attached to a filler goes with it ("um, what" → "what").
    public static func strippingFillers(_ text: String) -> String {
        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        var kept = tokens.filter { !fillers.contains(bare($0)) }
        for opener in openers {
            let count = opener.split(separator: " ").count
            guard kept.count > count else { continue }
            let head = kept.prefix(count).map(bare).joined(separator: " ")
            if head == opener {
                kept.removeFirst(count)
                break
            }
        }
        return kept.joined(separator: " ")
    }

    public static func hasCorrectionCue(_ text: String) -> Bool {
        let flat = " " + words(text).joined(separator: " ") + " "
        return correctionCues.contains { flat.contains(" " + $0 + " ") }
    }

    /// Every word of `output` appears in `input` at least as often as it is
    /// used: the model may have deleted, never added. An empty output fails.
    public static func usesOnlyWords(of input: String, _ output: String) -> Bool {
        let out = words(output)
        guard !out.isEmpty else { return false }
        var budget: [String: Int] = [:]
        for word in words(input) { budget[word, default: 0] += 1 }
        for word in out {
            guard let left = budget[word], left > 0 else { return false }
            budget[word] = left - 1
        }
        return true
    }

    private static func bare(_ token: String) -> String {
        words(token).first ?? ""
    }
}
