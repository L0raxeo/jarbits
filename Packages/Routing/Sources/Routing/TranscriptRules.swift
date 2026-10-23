import Foundation

/// What can be done to a spoken transcript without a model: the fillers
/// out, stutters collapsed, a self-correction noticed and, failing the
/// model, resolved by the one rule that usually holds (the words after the
/// cue replace as many words at the end of what came before), and a check
/// that a model's rewrite used only words that were said.
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
    /// Longer phrases first, so "no wait" is found before "no".
    public static let correctionCues: [String] = [
        "no wait", "wait no", "i mean", "i meant", "scratch that", "no not", "actually", "sorry",
    ]

    /// What trails off between the withdrawn words and the cue ("…Senegal?
    /// Or, no, sorry, I meant…"), and what tails the replacement.
    static let connectors: Set<String> = ["or", "and", "no", "wait", "sorry", "actually", "i", "mean", "meant", "um", "uh"]
    static let afterwords: [String] = ["is what i meant", "is what i mean", "instead", "rather", "i meant", "i mean"]

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
        return collapsingRepeats(kept).joined(separator: " ")
    }

    /// A stutter said twice in a row ("I meant I meant Taiwan, Taiwan") is
    /// kept once: runs of two or three words repeated back to back, and a
    /// single word only when the first copy carries punctuation, since
    /// "Duran Duran" and "please please me" are names, not stutters.
    static func collapsingRepeats(_ tokens: [String]) -> [String] {
        var kept = tokens
        var i = 0
        while i < kept.count {
            var collapsed = false
            for n in stride(from: 3, through: 1, by: -1) where i + 2 * n <= kept.count {
                if n == 1, kept[i].last?.isLetter != false { continue }
                if kept[i..<i + n].map(bare) == kept[i + n..<i + 2 * n].map(bare) {
                    // Keep the second copy: its punctuation is the one that closes the phrase.
                    kept.removeSubrange(i..<i + n)
                    collapsed = true
                    break
                }
            }
            if !collapsed { i += 1 }
        }
        return kept
    }

    /// The correction resolved without a model: the words after the last
    /// cue replace as many words at the end of what came before it ("go to
    /// texas, no wait, tokyo" → "go to tokyo"); a long replacement is the
    /// query restated and stands alone. The withdrawn phrase's closing
    /// punctuation is kept. Unchanged when there is no cue, or the cue
    /// leaves nothing on one side.
    public static func resolvingCorrection(_ text: String) -> String {
        var tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        // "…tokyo is what I meant": the afterword goes first, or its "I
        // meant" would be taken for the cue.
        while let count = trailing(afterwords, in: tokens) { tokens.removeLast(count) }
        guard let cue = lastCue(in: tokens) else { return text }
        var head = Array(tokens[..<cue.lowerBound])
        var tail = collapsingRepeats(Array(tokens[cue.upperBound...]))
        while let last = head.last, connectors.contains(bare(last)) { head.removeLast() }
        guard !head.isEmpty, !tail.isEmpty else { return text }
        guard tail.count <= 3, head.count > tail.count else { return tail.joined(separator: " ") }
        // The withdrawn phrase's full stop or question mark; a comma was just a pause.
        let closing = head[head.count - 1].reversed().prefix { !$0.isLetter && !$0.isNumber }.filter { ".?!".contains($0) }.reversed()
        head.removeLast(tail.count)
        var last = tail[tail.count - 1]
        while let end = last.last, !end.isLetter, !end.isNumber { last.removeLast() }
        tail[tail.count - 1] = last + String(closing)
        return (head + tail).joined(separator: " ")
    }

    /// Where the last cue stands in `tokens`, as a range of tokens.
    private static func lastCue(in tokens: [String]) -> Range<Int>? {
        let bare = tokens.map(bare)
        var found: Range<Int>?
        for start in bare.indices {
            for cue in correctionCues {
                let parts = cue.split(separator: " ").map(String.init)
                guard start + parts.count <= bare.count, Array(bare[start..<start + parts.count]) == parts else { continue }
                found = start..<start + parts.count
                break
            }
        }
        return found
    }

    /// The words that could make `text` a query: fillers, openers and
    /// closers out (an opener standing alone too), then only words of
    /// letters, two or more. "yeah mhm mmmmw" leaves "mmmmw", which a
    /// dictionary then has to vouch for.
    public static func candidateWords(_ text: String) -> [String] {
        let lone = Set((openers + closers).filter { !$0.contains(" ") })
        return words(strippingFillers(text)).filter { $0.count >= 2 && $0.allSatisfy(\.isLetter) && !lone.contains($0) }
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
