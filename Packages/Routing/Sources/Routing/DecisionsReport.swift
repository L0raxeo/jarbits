import Foundation

/// One routed query, as written to `decisions.jsonl` on the device.
public struct DecisionRecord: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var query: String
    public var decision: RouteDecision

    public init(timestamp: Date = .now, query: String, decision: RouteDecision) {
        self.timestamp = timestamp
        self.query = query
        self.decision = decision
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Summarises an exported `decisions.jsonl`: which formats real queries
/// triggered, how sure Jev was, and where it fell back.
public enum DecisionsReport {
    public static func parse(_ data: Data) throws -> [DecisionRecord] {
        try String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data($0.utf8)) }
    }

    public static func markdown(records: [DecisionRecord]) -> String {
        var out: [String] = []
        out.append("# Decisions")
        out.append("")
        guard !records.isEmpty else {
            out.append("No records.")
            return out.joined(separator: "\n") + "\n"
        }

        let asked = records.filter { $0.decision.suggested != nil }
        let errors = records.filter { if case .error = $0.decision.source { true } else { false } }
        let direct = records.filter { $0.decision.source == .directURL }
        let noKey = records.filter { $0.decision.source == .noKey }
        let latencies = asked.compactMap(\.decision.latencyMs).sorted()

        out.append("\(records.count) queries: \(asked.count) asked Jev, \(direct.count) addresses, \(noKey.count) without a key, \(errors.count) errors.")
        if let p50 = latencies.isEmpty ? nil : latencies[latencies.count / 2] {
            out.append("Median Jev latency \(p50) ms.")
        }
        if let first = records.map(\.timestamp).min(), let last = records.map(\.timestamp).max() {
            out.append("From \(first.formatted(date: .abbreviated, time: .shortened)) to \(last.formatted(date: .abbreviated, time: .shortened)).")
        }
        out.append("")
        out.append("## By format")
        out.append("")
        out.append("| Format | Picked | Acted on | Fell back (unsure) | Mean confidence | Recent queries |")
        out.append("|---|---|---|---|---|---|")
        for format in ResponseFormat.allCases {
            let picks = asked.filter { $0.decision.suggested == format }
            guard !picks.isEmpty else { continue }
            let acted = picks.filter { $0.decision.source == .jev }.count
            let unsure = picks.filter { $0.decision.source == .confidenceFallback }.count
            let confidences = picks.compactMap(\.decision.confidence)
            let mean = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
            let recent = picks.sorted { $0.timestamp > $1.timestamp }.prefix(3).map { "\"\($0.query)\"" }.joined(separator: ", ")
            out.append("| `\(format.rawValue)` | \(picks.count) | \(acted) | \(unsure) | \(mean.formatted(.number.precision(.fractionLength(2)))) | \(recent) |")
        }
        out.append("")

        if !errors.isEmpty {
            out.append("## Errors")
            out.append("")
            for record in errors.suffix(10) {
                if case let .error(message) = record.decision.source {
                    out.append("- \"\(record.query)\": \(message)")
                }
            }
            out.append("")
        }

        let unsure = asked.filter { $0.decision.source == .confidenceFallback }
        if !unsure.isEmpty {
            out.append("## Unsure picks (fell back to web)")
            out.append("")
            out.append("| Query | Pick | Confidence | Runner-up |")
            out.append("|---|---|---|---|")
            for record in unsure.sorted(by: { $0.timestamp > $1.timestamp }).prefix(20) {
                let pick = record.decision.suggested?.rawValue ?? "?"
                let confidence = record.decision.confidence.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "?"
                let runnerUp = record.decision.runnerUp.map { "`\($0.format.rawValue)` \($0.probability.formatted(.number.precision(.fractionLength(2))))" } ?? ""
                out.append("| \"\(record.query)\" | `\(pick)` | \(confidence) | \(runnerUp) |")
            }
            out.append("")
        }
        return out.joined(separator: "\n") + "\n"
    }
}
