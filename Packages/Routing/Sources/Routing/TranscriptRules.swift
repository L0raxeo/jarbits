import Foundation

/// What can be done to a spoken transcript without a model: the fillers
/// out, a self-correction noticed, and a check that a model's rewrite used
/// only words that were said. The correction itself is left to the model:
/// how far back "no wait tokyo" reaches is a judgement, not a rule.
public enum TranscriptRules {
    /// Sounds, never words: safe to drop wherever they stand. Matched on
    /// the letters alone, so "Mm-hmm," is "mmhmm".
    public static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "er", "erm", "ah", "eh", "hmm", "hm", "mm", "mhm", "mmhm", "mmhmm", "uhhuh", "uhuh",
    ]

    /// Acknowledgements and lead-ins, stripped from the very start as long
    /// as they keep coming ("Yeah. Okay, so what is…"); "so" and "well" mean
    /// something later on. Longer phrases first, so "all right" is not "all".
    public static let openers: [String] = [
        "let me see", "let's see", "you know", "all right", "alright", "okay", "ok", "yeah", "yes", "yep", "yup", "so", "well",
    ]

    /// Sign-offs, stripped from the very end.
    public static let closers: [String] = ["thank you", "thanks", "please"]

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

    /// `text` without standalone fillers, without openers at the start and
    /// without closers at the end. Punctuation attached to a dropped word
    /// goes with it ("um, what" → "what"). Never the whole text: a query
    /// that is nothing but "well" stays "well".
    public static func strippingFillers(_ text: String) -> String {
        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        var kept = tokens.filter { !fillers.contains(bare($0)) }
        while let count = leading(openers, in: kept) {
            kept.removeFirst(count)
        }
        while let count = trailing(closers, in: kept) {
            kept.removeLast(count)
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

    /// How many tokens the first matching phrase takes at the start of
    /// `tokens`, leaving at least one behind; nil when none matches.
    private static func leading(_ phrases: [String], in tokens: [String]) -> Int? {
        for phrase in phrases {
            let count = phrase.split(separator: " ").count
            guard tokens.count > count else { continue }
            if tokens.prefix(count).map(bare).joined(separator: " ") == phrase { return count }
        }
        return nil
    }

    private static func trailing(_ phrases: [String], in tokens: [String]) -> Int? {
        for phrase in phrases {
            let count = phrase.split(separator: " ").count
            guard tokens.count > count else { continue }
            if tokens.suffix(count).map(bare).joined(separator: " ") == phrase { return count }
        }
        return nil
    }
}
