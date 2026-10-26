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
        let device = results.filter { if case .local = $0.decision.source { true } else { false } }.count
        let addresses = results.filter { $0.decision.source == .directURL }.count
        let fromCache = results.filter(\.cached).count
        let asked = results.count - device - addresses - fromCache - uncached
        var counts = "\(device) on the device, \(addresses) \(addresses == 1 ? "address" : "addresses"), \(fromCache) from cache, \(asked) asked Jev"
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
        for format in ResponseFormat.allCases {
            let rows = results.filter { $0.expected == format }
            guard !rows.isEmpty else { continue }
            let ok = rows.filter { $0.status == .pass }.count
            out.append("  \(format.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)) \(ok)/\(rows.count)")
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// Why the decision came out as it did: the rule, the address, or the
    /// threshold that was decisive, with the value against it.
    public static func gate(_ decision: RouteDecision, floor: Double, recencyThreshold: Double) -> String {
        func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
        func compare(_ label: String, _ value: Double?, _ threshold: Double) -> String? {
            guard let value else { return nil }
            return "\(label) \(number(value)) \(value >= threshold ? "≥" : "<") \(threshold.formatted())"
        }
        let confidence = compare("confidence", decision.confidence, floor)
        switch decision.source {
        case let .local(rule): return "device rule \(rule)"
        case .directURL: return "address"
        case .noKey: return "no key"
        case let .error(message): return "error: \(message)"
        case .rejection: return compare("rejects", decision.rejection, JevRouting.rejectionThreshold) ?? "rejects"
        case .continuation: return [compare("continues", decision.continuation, JevRouting.continuationThreshold), confidence].compactMap { $0 }.joined(separator: ", ")
        case .recencyFallback: return [compare("recency", decision.recency, recencyThreshold), confidence].compactMap { $0 }.joined(separator: ", ")
        case .confidenceFallback: return confidence ?? "confidence below the floor"
        case .answerSplit:
            let mass = (decision.probabilities[ResponseFormat.oneLine.rawValue] ?? 0) + (decision.probabilities[ResponseFormat.narrative.rawValue] ?? 0)
            return [confidence, compare("answers together", mass, JevRouting.answerMassFloor)].compactMap { $0 }.joined(separator: ", ")
        case .jev:
            var parts = [confidence]
            if let continuation = decision.continuation, continuation >= JevRouting.continuationThreshold {
                parts.append(compare("continues", continuation, JevRouting.continuationThreshold))
            }
            return parts.compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// The three most likely formats: "image .46  web_results .41  narrative .09".
    public static func spread(_ decision: RouteDecision) -> String {
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
            "\(result.decision.format.rawValue) (\(result.decision.source.kind))"
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
