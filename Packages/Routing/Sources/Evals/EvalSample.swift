import Foundation
import Routing

/// Unlabelled queries to stress the router with: the checked-in
/// `Evals/pool.txt`, or the queries of a log exported from the phone.
public enum QueryPool {
    /// One query per line. Blank lines and lines starting with `#` are
    /// skipped; a query that appears twice is kept once, where it first
    /// appeared, so a file organised by format can repeat itself harmlessly.
    public static func parse(_ data: Data) -> [String] {
        var seen: Set<String> = []
        var queries: [String] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
            let query = line.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty, !query.hasPrefix("#") else { continue }
            if seen.insert(query).inserted { queries.append(query) }
        }
        return queries
    }

    /// The queries of an exported `decisions.jsonl`, oldest first, each
    /// once. The thread or site that was on screen is not in the log, so
    /// every query is routed as if typed fresh.
    public static func parseLog(_ data: Data) throws -> [String] {
        var seen: Set<String> = []
        return try DecisionsReport.parse(data).map(\.query).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// SplitMix64: a small seeded generator, so the same seed draws the same
/// sample on any machine. `SystemRandomNumberGenerator` cannot be seeded.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// One sampled query after routing, with what makes it worth a look.
public struct TriageRow: Equatable, Sendable {
    /// Why a row is worth a human's eye. A threshold the value came close
    /// to is a label that could flip on the next model or criterion edit;
    /// a gate that fired hid Jev's pick; a device rule never asked Jev.
    public enum Doubt: Equatable, Sendable {
        /// Confidence passed the floor by this little.
        case nearFloor(by: Double)
        /// Confidence missed the floor by this much: web results were shown.
        case confidenceFallback(by: Double)
        /// Recency stayed under the threshold by this little on an answered pick.
        case nearRecency(by: Double)
        /// Recency reached the threshold by this much: web results were shown.
        case recencyFallback(by: Double)
        case deviceRule(String)
        case error(String)
        /// Jev was not asked and the cache had no answer.
        case uncached

        /// How close the deciding value was to its threshold; nil when no
        /// threshold was involved.
        public var margin: Double? {
            switch self {
            case let .nearFloor(by), let .confidenceFallback(by), let .nearRecency(by), let .recencyFallback(by): by
            case .deviceRule, .error, .uncached: nil
            }
        }
    }

    public struct RunnerUp: Equatable, Sendable {
        public var format: String
        public var probability: Double

        public init(format: String, probability: Double) {
            self.format = format
            self.probability = probability
        }
    }

    public var query: String
    public var result: EvalResult
    public var doubts: [Doubt]
    /// The second most likely format, behind the pick.
    public var runnerUp: RunnerUp?

    public var decision: RouteDecision { result.decision }

    /// A doubt about the routing itself, as opposed to a run that failed.
    public var isDoubtful: Bool {
        doubts.contains { doubt in
            switch doubt {
            case .nearFloor, .confidenceFallback, .nearRecency, .recencyFallback, .deviceRule: true
            case .error, .uncached: false
            }
        }
    }

    /// Jev was needed and did not answer: a failure or a cold cache.
    public var isUnrouted: Bool {
        doubts.contains { doubt in
            switch doubt {
            case .error, .uncached: true
            case .nearFloor, .confidenceFallback, .nearRecency, .recencyFallback, .deviceRule: false
            }
        }
    }

    /// The smallest distance to a threshold among the doubts.
    public var margin: Double? {
        doubts.compactMap(\.margin).min()
    }
}

/// A stress run: `n` unlabelled queries through the same chain as the eval,
/// read as a triage list rather than pass/fail. Nothing here is a verdict;
/// a row the reader agrees with becomes a golden-set line as printed, and
/// one they disagree with becomes the same line with the format corrected.
public enum EvalSample {
    /// How close to a threshold counts as doubtful.
    public static let band = 0.15

    /// The default sample size.
    public static let defaultCount = 50

    /// The day as a number (20261023) in the zone given, so a run repeated
    /// the same day draws the same queries and the cache answers it, while
    /// the next day draws fresh ones.
    public static func seed(for date: Date, zone: TimeZone) -> UInt64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt64((parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0))
    }

    /// `count` distinct queries from the pool, in a random order fixed by
    /// `seed`; the whole pool, shuffled, when `count` reaches its size.
    public static func sample(_ pool: [String], count: Int, seed: UInt64) -> [String] {
        var generator = SeededGenerator(seed: seed)
        var remaining = pool
        let taken = min(max(count, 0), remaining.count)
        for index in 0..<taken {
            remaining.swapAt(index, Int.random(in: index..<remaining.count, using: &generator))
        }
        return Array(remaining.prefix(taken))
    }

    /// The unlabelled case the runner takes: the expected format is a
    /// placeholder and the pass/fail it produces is ignored.
    public static func evalCase(for query: String) -> EvalCase {
        EvalCase(query: query, format: .fallback)
    }

    /// Routes the queries in order through the runner, then sorts the rows
    /// most doubtful first.
    public static func run(_ queries: [String], runner: EvalRunner) async -> [TriageRow] {
        var rows: [TriageRow] = []
        for query in queries {
            let result = await runner.run(evalCase(for: query))
            rows.append(row(result, floor: runner.floor, recencyThreshold: runner.recencyThreshold))
        }
        return sorted(rows)
    }

    public static func row(_ result: EvalResult, floor: Double, recencyThreshold: Double) -> TriageRow {
        let decision = result.decision
        var doubts: [TriageRow.Doubt] = []
        if result.status == .uncached {
            doubts.append(.uncached)
        } else {
            switch decision.source {
            case let .local(rule): doubts.append(.deviceRule(rule))
            case let .error(message): doubts.append(.error(message))
            case .confidenceFallback:
                if let confidence = decision.confidence { doubts.append(.confidenceFallback(by: floor - confidence)) }
            case .recencyFallback:
                if let recency = decision.recency { doubts.append(.recencyFallback(by: recency - recencyThreshold)) }
            case .jev, .continuation, .rejection, .directURL, .noKey:
                break
            }
            if decision.source != .confidenceFallback, let confidence = decision.confidence, confidence >= floor, confidence - floor < band {
                doubts.append(.nearFloor(by: confidence - floor))
            }
            // Recency only gates the formats a model answers; on a page or a
            // picture it is moot, however close it came.
            if decision.source != .recencyFallback, let recency = decision.recency, decision.suggested?.isAnswered == true,
               recency < recencyThreshold, recencyThreshold - recency < band {
                doubts.append(.nearRecency(by: recencyThreshold - recency))
            }
        }
        let ranked = decision.probabilities.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
        let runnerUp = ranked.dropFirst().first.map { TriageRow.RunnerUp(format: $0.key, probability: $0.value) }
        return TriageRow(query: result.query, result: result, doubts: doubts, runnerUp: runnerUp)
    }

    /// Most doubtful first: a value close to a threshold or a gate that
    /// fired, the closest call first; then the device rules; then the rows
    /// that did not route (errors, then not cached); then the sure rows,
    /// least sure first. Ties keep the query order.
    public static func sorted(_ rows: [TriageRow]) -> [TriageRow] {
        func rank(_ row: TriageRow) -> (Int, Double, String) {
            if let margin = row.margin { return (0, margin, row.query) }
            if row.doubts.contains(where: { if case .deviceRule = $0 { true } else { false } }) { return (1, 0, row.query) }
            if row.doubts.contains(where: { if case .error = $0 { true } else { false } }) { return (2, 0, row.query) }
            if row.doubts.contains(.uncached) { return (3, 0, row.query) }
            return (4, row.decision.confidence ?? 1, row.query)
        }
        return rows.enumerated().sorted { lhs, rhs in
            let (l, r) = (rank(lhs.element), rank(rhs.element))
            if l.0 != r.0 { return l.0 < r.0 }
            if l.1 != r.1 { return l.1 < r.1 }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The row as a golden-set line, labelled with what the app did: paste
    /// it into `routing.jsonl` as is when that was right, or with the
    /// format corrected when it was not. A device rule is pinned as its
    /// source, as the golden set does.
    public static func goldenLine(_ row: TriageRow) -> String {
        let query = String(decoding: (try? OrderedJSON.encode(row.query)) ?? Data("\"\"".utf8), as: UTF8.self)
        var line = "{\"query\": \(query), \"format\": \"\(row.decision.format.rawValue)\""
        if case .local = row.decision.source {
            line += ", \"source\": \"\(row.decision.source.kind)\""
        }
        return line + "}"
    }

    /// What was done and what to doubt about it, in one line each.
    public static func describe(_ row: TriageRow, floor: Double, recencyThreshold: Double) -> (acted: String, why: String) {
        func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
        let decision = row.decision
        var acted = "acted \(decision.format.rawValue) (\(decision.source.kind))"
        if let text = row.result.localText { acted += ": \"\(text)\"" }
        if let term = row.result.searchTerm, term != row.query { acted += ", term \"\(term)\"" }
        if let subject = row.result.imageSubject, subject != row.query { acted += ", subject \"\(subject)\"" }
        if let site = row.result.siteName, site != row.query { acted += ", site \"\(site)\"" }
        if let suggested = decision.suggested, suggested != decision.format { acted += ", picked \(suggested.rawValue)" }
        if let confidence = decision.confidence { acted += ", confidence \(number(confidence))" }
        if let recency = decision.recency { acted += ", recency \(number(recency))" }
        if let runnerUp = row.runnerUp { acted += ", runner-up \(runnerUp.format) \(short(runnerUp.probability))" }

        var reasons: [String] = []
        for doubt in row.doubts {
            switch doubt {
            case let .nearFloor(by): reasons.append("confidence \(number(by)) over the floor \(floor.formatted())")
            case let .confidenceFallback(by): reasons.append("confidence \(number(by)) under the floor \(floor.formatted()): web results")
            case let .nearRecency(by): reasons.append("recency \(number(by)) under the threshold \(recencyThreshold.formatted())")
            case let .recencyFallback(by): reasons.append("recency \(number(by)) over the threshold \(recencyThreshold.formatted()): web results")
            case let .deviceRule(rule): reasons.append("device rule \(rule): Jev not asked")
            case let .error(message): reasons.append("error: \(message)")
            case .uncached: reasons.append("not cached (set TYPESAFE_API_KEY to ask Jev)")
            }
        }
        var why = reasons.isEmpty ? EvalReport.gate(decision, floor: floor, recencyThreshold: recencyThreshold) : reasons.joined(separator: "; ")
        let spread = EvalReport.spread(decision)
        if !spread.isEmpty { why += "   " + spread }
        return (acted, why)
    }

    private static func short(_ probability: Double) -> String {
        probability.formatted(.number.precision(.fractionLength(2))).replacingOccurrences(of: "^0", with: "", options: .regularExpression)
    }

    /// The run as plain text: one summary line, then the rows in three
    /// groups, each as what was done, why to doubt it, and the line to
    /// paste into the golden set. A row Jev never answered has no pick to
    /// label and gets one line saying why.
    public static func text(rows: [TriageRow], poolSize: Int, source: String, seed: UInt64, floor: Double, recencyThreshold: Double, model: String) -> String {
        var out: [String] = []
        let doubtful = rows.filter(\.isDoubtful)
        let unrouted = rows.filter { !$0.isDoubtful && $0.isUnrouted }
        let sure = rows.filter { !$0.isDoubtful && !$0.isUnrouted }
        // Each row in one bucket: how it was answered, or why it was not.
        var device = 0, addresses = 0, fromCache = 0, uncached = 0, errors = 0, asked = 0
        for row in rows {
            if row.result.status == .uncached { uncached += 1; continue }
            switch row.decision.source {
            case .local: device += 1
            case .directURL: addresses += 1
            case .error: errors += 1
            default: if row.result.cached { fromCache += 1 } else { asked += 1 }
            }
        }
        var counts = "\(device) on the device, \(addresses) \(addresses == 1 ? "address" : "addresses"), \(fromCache) from cache, \(asked) asked Jev"
        if errors > 0 { counts += ", \(errors) \(errors == 1 ? "error" : "errors")" }
        if uncached > 0 { counts += ", \(uncached) not cached" }
        out.append("sample \(source): \(rows.count) of \(poolSize) queries, seed \(seed), \(doubtful.count) doubtful (floor \(floor.formatted()), recency \(recencyThreshold.formatted()), \(model); \(counts))")

        func append(_ title: String, _ group: [TriageRow]) {
            guard !group.isEmpty else { return }
            out.append("")
            out.append("\(title) (\(group.count)):")
            for row in group {
                out.append("  \"\(row.query)\"")
                let (acted, why) = describe(row, floor: floor, recencyThreshold: recencyThreshold)
                guard !row.isUnrouted else {
                    // No pick to label: one line saying why, and no golden line.
                    out.append("      not routed: " + why)
                    continue
                }
                out.append("      " + acted)
                out.append("      " + why)
                out.append("      " + goldenLine(row))
            }
        }
        append("doubtful", doubtful)
        append("not routed", unrouted)
        append("sure", sure)
        return out.joined(separator: "\n") + "\n"
    }
}
