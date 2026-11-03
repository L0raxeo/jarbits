import Foundation

/// The ear test: two runs of the same cases (`report plans --out`, before
/// and after a change) laid side by side with the sides shuffled per case,
/// so the listener picks without knowing which is which; the key says
/// which side was which, and `score` reads the picks against it.
public enum Blind {
    public struct Pair: Codable, Equatable, Sendable {
        public var name: String
        public var query: String
        /// What each side said: every `say`, `ask` and answer query of the
        /// first round, joined.
        public var a: String
        public var b: String
        /// Which run side A came from: "old" or "new".
        public var aIs: String
    }

    /// What a run said for a case, for the ear: the text of `say`, the
    /// question of `ask`, the query handed to an answer; other calls by
    /// name, so a different route is heard as such.
    public static func said(_ result: PlanResult) -> String {
        let parts = result.calls.compactMap { call -> String? in
            switch call.name {
            case "say": return call.arguments["text"]
            case "ask": return call.arguments["question"].map { "(asks) " + $0 + (call.arguments["options"].map { " [\($0)]" } ?? "") }
            case "narrative", "one_line": return call.arguments["query"].map { "(answers) " + $0 }
            case "done": return nil
            default: return "(\(call.name))"
            }
        }
        return parts.isEmpty ? "(nothing said)" : parts.joined(separator: " | ")
    }

    /// Cases in both runs, in the old run's order, each with its sides in
    /// an order fixed by the seed.
    public static func pairs(old: [PlanResult], new: [PlanResult], seed: UInt64) -> [Pair] {
        let after = Dictionary(new.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        var generator = SeededGenerator(seed: seed)
        return old.compactMap { before in
            guard let result = after[before.name] else { return nil }
            let oldFirst = Bool.random(using: &generator)
            let oldText = said(before), newText = said(result)
            return Pair(name: before.name, query: before.query, a: oldFirst ? oldText : newText, b: oldFirst ? newText : oldText, aIs: oldFirst ? "old" : "new")
        }
    }

    /// The sheet to read: numbered, the two sides unlabelled.
    public static func sheet(_ pairs: [Pair]) -> String {
        var out: [String] = ["\(pairs.count) cases. For each, which sounds more like him: A, B, or - for no preference.", ""]
        for (index, pair) in pairs.enumerated() {
            out.append("\(index + 1). \"\(pair.query)\"")
            out.append("   A: \(pair.a)")
            out.append("   B: \(pair.b)")
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// Picks as typed, one per case in order (`A`, `B` or `-`, separated by
    /// anything), scored against the key.
    public static func score(_ picks: String, key: [Pair]) -> String {
        let letters = picks.uppercased().filter { "AB-".contains($0) }.map(String.init)
        var new = 0, old = 0, neither = 0
        var lines: [String] = []
        for (index, pair) in key.enumerated() {
            guard index < letters.count else { break }
            let pick = letters[index]
            let chosen = pick == "-" ? "neither" : ((pick == "A") == (pair.aIs == "old") ? "old" : "new")
            switch chosen {
            case "new": new += 1
            case "old": old += 1
            default: neither += 1
            }
            lines.append("\(index + 1). \(chosen) (\(pick))  \"\(pair.query)\"")
        }
        let counted = min(letters.count, key.count)
        return (["\(counted) of \(key.count) judged: new \(new), old \(old), no preference \(neither)."] + lines).joined(separator: "\n") + "\n"
    }
}
