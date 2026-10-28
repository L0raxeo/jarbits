import Foundation
import Routing

/// The run as plain text, in the voice of `report route`: one summary line,
/// the misses with the gate that decided and the spread, the counts per
/// expected format, and what flipped against a baseline.
public enum EvalReport {
    public static func text(results: [EvalResult], file: String, floor: Double, recencyThreshold: Double, model: String) -> String {
        var out: [String] = []
        let passed = results.filter { $0.status == .pass }.count
        let failed = results.filter { $0.status == .fail }.count
        let uncached = results.filter { $0.status == .uncached }.count
        let addresses = results.filter { $0.decision.source == .directURL }.count
        let fromCache = results.filter(\.cached).count
        let asked = results.count - addresses - fromCache - uncached
        var counts = "\(addresses) \(addresses == 1 ? "address" : "addresses"), \(fromCache) from cache, \(asked) asked Jev"
        if uncached > 0 { counts += ", \(uncached) not cached" }
        out.append("eval \(file): \(results.count) cases, \(passed) passed, \(failed) failed\(uncached > 0 ? ", \(uncached) not cached" : "") (floor \(floor.formatted()), recency \(recencyThreshold.formatted()), \(model); \(counts))")

        let misses = results.filter { $0.status != .pass }
        if !misses.isEmpty {
            out.append("")
            out.append("misses:")
            for result in misses {
                out.append("  \"\(result.name)\"")
                out.append("      " + result.failures.joined(separator: "; "))
                if result.decision.suggested != nil {
                    out.append("      " + gate(result.decision, floor: floor, recencyThreshold: recencyThreshold) + "   " + spread(result.decision))
                }
            }
        }

        out.append("")
        out.append("by expected format:")
        for format in Instinct.allCases {
            let rows = results.filter { $0.expected == format }
            guard !rows.isEmpty else { continue }
            let ok = rows.filter { $0.status == .pass }.count
            out.append("  \(format.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)) \(ok)/\(rows.count)")
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// Why the decision came out as it did: the threshold that was
    /// decisive, with the value against it, and what the answer instincts
    /// will make of the recency.
    public static func gate(_ decision: Pick, floor: Double, recencyThreshold: Double) -> String {
        func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
        func compare(_ label: String, _ value: Double?, _ threshold: Double) -> String? {
            guard let value else { return nil }
            return "\(label) \(number(value)) \(value >= threshold ? "≥" : "<") \(threshold.formatted())"
        }
        let confidence = compare("confidence", decision.confidence, floor)
        // "chain 1 of 2, relevance 0.83 ≥ 0.5": how far back the query reached.
        let chain: String? = decision.relevance.flatMap { relevance in
            guard decision.chainedCount > 0 else { return nil }
            return ["chain \(decision.chainedCount) of \(relevance.count)", compare("relevance", relevance.last, EngineRequest.relevanceThreshold)].compactMap { $0 }.joined(separator: ", ")
        }
        let reasoning: String? = decision.reasoningWanted ? decision.reasoning.map { "reasoning \(number($0)) (wanted)" } : nil
        let recency: String? = decision.instinct.isAnswered ? compare("recency", decision.recency, recencyThreshold).map { decision.recent ? $0 + " (the instinct shows web results)" : $0 } : nil
        switch decision.source {
        case .directURL: return "address"
        case .noKey: return "no key"
        case .plan: return "step of a plan"
        case let .error(message): return "error: \(message)"
        case .confidenceFallback: return [confidence ?? "confidence below the floor", reasoning].compactMap { $0 }.joined(separator: ", ")
        case .jev: return [confidence, recency, chain].compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// The three most likely formats: "image .46  web_results .41  narrative .09".
    public static func spread(_ decision: Pick) -> String {
        decision.probabilities
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { "\($0.key) \($0.value.formatted(.number.precision(.fractionLength(2))).replacingOccurrences(of: "^0", with: "", options: .regularExpression))" }
            .joined(separator: "  ")
    }

    public static func text(diff: EvalDiff, baseline: String) -> String {
        var out: [String] = []
        out.append("against \(baseline): \(diff.regressions.count) \(diff.regressions.count == 1 ? "regression" : "regressions"), \(diff.fixes.count) \(diff.fixes.count == 1 ? "fix" : "fixes"), \(diff.added.count) new, \(diff.dropped.count) dropped")
        func describe(_ result: EvalResult) -> String {
            "\(result.decision.instinct.rawValue) (\(result.decision.source.kind))"
        }
        if !diff.regressions.isEmpty {
            out.append("  regressions:")
            for flip in diff.regressions {
                out.append("    \"\(flip.name)\": was \(describe(flip.before)), now \(describe(flip.after))")
            }
        }
        if !diff.fixes.isEmpty {
            out.append("  fixes:")
            for flip in diff.fixes {
                out.append("    \"\(flip.name)\": was \(describe(flip.before)), now \(describe(flip.after))")
            }
        }
        if !diff.added.isEmpty {
            out.append("  new: " + diff.added.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        if !diff.dropped.isEmpty {
            out.append("  dropped: " + diff.dropped.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        return out.joined(separator: "\n") + "\n"
    }
}
