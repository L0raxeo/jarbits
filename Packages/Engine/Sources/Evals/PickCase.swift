import Foundation
import Engine

/// One case of the fact pick's set: a request, the exchanges before it,
/// the facts the answer needs (every one must be picked, at every pool
/// size) and the facts that may help (picked or not, never counted as
/// extras). The facts themselves come from the pool file; a case whose
/// needed or helpful facts are not in the pool has them added.
public struct PickCase: Codable, Equatable, Sendable {
    public var query: String
    public var exchanges: [Exchange]?
    public var needed: [String]
    public var helpful: [String]?
    public var note: String?

    public init(query: String, exchanges: [Exchange]? = nil, needed: [String], helpful: [String]? = nil, note: String? = nil) {
        self.query = query
        self.exchanges = exchanges
        self.needed = needed
        self.helpful = helpful
        self.note = note
    }

    public var name: String {
        var name = query
        if let last = exchanges?.last { name += " after \"\(last.query)\"" }
        return name
    }
}

public enum PickSet {
    public static func parse(_ data: Data) throws -> [PickCase] {
        var cases: [PickCase] = []
        var names: Set<String> = []
        let decoder = JSONDecoder()
        for (index, line) in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let number = index + 1
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let pickCase: PickCase
            do {
                pickCase = try decoder.decode(PickCase.self, from: Data(line.utf8))
            } catch {
                throw EvalSetError.malformed(line: number, reason: String(describing: error))
            }
            guard names.insert(pickCase.name).inserted else { throw EvalSetError.duplicateName(line: number, name: pickCase.name) }
            cases.append(pickCase)
        }
        return cases
    }
}

/// The facts a run draws from: the pool file (one fact per line, `#`
/// comments and blanks skipped, each once), and the subsets of it a case
/// is measured at.
public enum PickPool {
    /// A fixed date for every pool fact, a month before the example clock,
    /// so no fact reads as just noted and the request bytes are stable.
    public static let factDate = Date(timeIntervalSince1970: 1_792_600_000 - 30 * 86_400)

    public static func parse(_ data: Data) -> [String] {
        QueryPool.parse(data)
    }

    /// Every fact to score for a case: the pool in file order, then any
    /// needed or helpful fact the pool lacks. The same list for every case
    /// of a run, so the cache keys differ only by the query and exchanges.
    public static func facts(pool: [String], adding extra: [String]) -> [Fact] {
        var seen = Set(pool.map(Fact.key))
        var texts = pool
        for text in extra where seen.insert(Fact.key(text)).inserted { texts.append(text) }
        return texts.map { Fact(text: $0, source: .inferred, madeBy: "", date: factDate) }
    }

    /// The facts a case is measured against at `size`: its needed and
    /// helpful facts, then others drawn from the pool in an order fixed by
    /// the case's name and the size, so a run repeats exactly.
    public static func subset(for pickCase: PickCase, pool: [Fact], size: Int) -> Set<String> {
        let keep = Set((pickCase.needed + (pickCase.helpful ?? [])).map(Fact.key))
        var others = pool.map(\.text).filter { !keep.contains(Fact.key($0)) }
        var generator = SeededGenerator(seed: stableHash("\(pickCase.name)@\(size)"))
        others.shuffle(using: &generator)
        let room = max(size - keep.count, 0)
        return keep.union(others.prefix(room).map(Fact.key))
    }

    /// FNV-1a over the UTF-8 bytes: `hashValue` changes per process.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

public struct PickResult: Codable, Equatable, Sendable {
    /// The case measured at one pool size.
    public struct AtSize: Codable, Equatable, Sendable {
        public var size: Int
        /// How many facts went.
        public var sent: Int
        public var neededReached: Int
        public var neededTotal: Int
        public var helpfulReached: Int
        /// Facts that went which were neither needed nor helpful.
        public var extras: Int
        public var passed: Bool
        /// The needed facts that did not go, with their scores.
        public var missed: [String]
    }

    public var name: String
    public var query: String
    public var sizes: [AtSize]
    /// The lowest score among the needed facts, nil with none needed.
    public var lowestNeeded: Double?
    public var cached: Bool
    /// The slowest request's time, since the app sends them at once.
    public var latencyMs: Int
    public var requests: Int
    public var status: EvalStatus
    public var failures: [String]
}

/// Scores the whole pool for each case, as the app does it (requests of
/// `FactPicking.chunk`, one `score` question per fact), from the cache when
/// the request bytes are known, else one request per chunk; then measures
/// the selection at each pool size from those scores, since a fact's score
/// barely depends on its neighbours (largest change 0.04 across 15 and 200
/// facts in the Python run of 2026-11-02).
public struct PickRunner: Sendable {
    /// Nil never touches the network: a miss in the cache is `uncached`.
    public var client: JevClient?
    public var cache: JevCache
    public var model: String
    public var locale: Locale
    public var threshold: Double
    public var limit: Int
    public var sizes: [Int]

    public static let defaultSizes = [15, 200, 1000]

    public init(client: JevClient?, cache: JevCache, locale: Locale = Locale(identifier: "en_US"), threshold: Double = FactPicking.threshold, limit: Int = FactPicking.maxSent, sizes: [Int] = PickRunner.defaultSizes) {
        self.client = client
        self.cache = cache
        self.model = client?.model ?? FactPicking.model
        self.locale = locale
        self.threshold = threshold
        self.limit = limit
        self.sizes = sizes
    }

    public func run(_ cases: [PickCase], pool: [String]) async -> [PickResult] {
        var results: [PickResult] = []
        for pickCase in cases { results.append(await run(pickCase, pool: pool)) }
        return results
    }

    public func run(_ pickCase: PickCase, pool: [String]) async -> PickResult {
        let facts = PickPool.facts(pool: pool, adding: pickCase.needed + (pickCase.helpful ?? []))
        let exchanges = pickCase.exchanges ?? []
        var scores: [FactScore] = []
        var cached = true
        var latency = 0
        var requests = 0
        for part in FactPicking.chunks(facts) {
            let request = FactPicking.request(for: pickCase.query, facts: part, exchanges: exchanges, locale: locale, model: model)
            let key: String
            do {
                key = try JevCache.key(for: request)
            } catch {
                return failed(pickCase, "encode: \(error)")
            }
            let response: SystemOneResponse
            if let entry = cache.entry(for: key) {
                response = entry.response
                latency = max(latency, entry.latencyMs)
            } else if let client {
                let clock = ContinuousClock()
                let start = clock.now
                let data: Data
                do {
                    data = try await client.systemOneData(request)
                } catch {
                    return failed(pickCase, error.summary)
                }
                let took = Int((clock.now - start) / .milliseconds(1))
                do {
                    response = try JSONDecoder().decode(SystemOneResponse.self, from: data)
                } catch {
                    return failed(pickCase, "decoding: \(error)")
                }
                try? cache.store(key: key, request: request, response: data, latencyMs: took)
                latency = max(latency, took)
                cached = false
            } else {
                return PickResult(name: pickCase.name, query: pickCase.query, sizes: [], lowestNeeded: nil, cached: false, latencyMs: 0, requests: 0, status: .uncached, failures: ["not cached: set TYPESAFE_API_KEY to ask Jev"])
            }
            scores += FactPicking.scores(from: response, facts: part)
            requests += 1
        }
        return measure(pickCase, scores: scores, cached: cached, latencyMs: latency, requests: requests)
    }

    /// The selection at each size, from the scores: pure, so a threshold or
    /// cap sweep re-measures cached answers.
    public func measure(_ pickCase: PickCase, scores: [FactScore], cached: Bool, latencyMs: Int, requests: Int) -> PickResult {
        let needed = Set(pickCase.needed.map(Fact.key))
        let helpful = Set((pickCase.helpful ?? []).map(Fact.key))
        let byKey = Dictionary(scores.map { (Fact.key($0.fact.text), $0.score) }, uniquingKeysWith: { first, _ in first })
        var sizes: [PickResult.AtSize] = []
        var failures: [String] = []
        for size in self.sizes {
            let subset = PickPool.subset(for: pickCase, pool: scores.map(\.fact), size: size)
            let among = scores.filter { subset.contains(Fact.key($0.fact.text)) }
            let selected = Set(FactPicking.select(among, threshold: threshold, limit: limit).map { Fact.key($0.text) })
            let missed = pickCase.needed.filter { !selected.contains(Fact.key($0)) }
            let at = PickResult.AtSize(
                size: size,
                sent: selected.count,
                neededReached: needed.count - missed.count,
                neededTotal: needed.count,
                helpfulReached: selected.intersection(helpful).count,
                extras: selected.subtracting(needed).subtracting(helpful).count,
                passed: missed.isEmpty,
                missed: missed.map { "\"\($0)\" \(format(byKey[Fact.key($0)] ?? 0))" }
            )
            sizes.append(at)
            if !missed.isEmpty { failures.append("at \(size): missed \(at.missed.joined(separator: ", "))") }
        }
        let lowest = pickCase.needed.compactMap { byKey[Fact.key($0)] }.min()
        return PickResult(name: pickCase.name, query: pickCase.query, sizes: sizes, lowestNeeded: lowest, cached: cached, latencyMs: latencyMs, requests: requests, status: failures.isEmpty ? .pass : .fail, failures: failures)
    }

    private func failed(_ pickCase: PickCase, _ reason: String) -> PickResult {
        PickResult(name: pickCase.name, query: pickCase.query, sizes: [], lowestNeeded: nil, cached: false, latencyMs: 0, requests: 0, status: .fail, failures: ["error: \(reason)"])
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}

public enum PickReport {
    public static func text(results: [PickResult], file: String, pool: String, poolSize: Int, model: String, threshold: Double, limit: Int) -> String {
        var out: [String] = []
        let passed = results.filter { $0.status == .pass }.count
        let failed = results.filter { $0.status == .fail }.count
        let uncached = results.filter { $0.status == .uncached }.count
        let fromCache = results.filter(\.cached).count
        let asked = results.filter { !$0.cached && $0.status != .uncached }.count
        out.append("picks \(file): \(results.count) cases over \(pool) (\(poolSize) facts), \(passed) passed, \(failed) failed\(uncached > 0 ? ", \(uncached) not cached" : "") (\(model), bar \(threshold.formatted()), at most \(limit); \(fromCache) from cache, \(asked) asked Jev)")
        let measured = results.filter { $0.status != .uncached && !$0.sizes.isEmpty }
        if !measured.isEmpty {
            out.append("")
            out.append("by pool size: needed facts reached | cases with every needed fact | facts sent, mean / median / most | extras on cases needing none")
            let sizes = measured.first.map { $0.sizes.map(\.size) } ?? []
            for size in sizes {
                let rows = measured.compactMap { result in result.sizes.first { $0.size == size } }
                let needed = rows.reduce(0) { $0 + $1.neededReached }
                let total = rows.reduce(0) { $0 + $1.neededTotal }
                let whole = rows.filter(\.passed).count
                let sent = rows.map(\.sent).sorted()
                let mean = Double(sent.reduce(0, +)) / Double(max(sent.count, 1))
                let median = sent.isEmpty ? 0 : sent[sent.count / 2]
                let traps = rows.filter { $0.neededTotal == 0 }.map(\.extras)
                let trapMean = traps.isEmpty ? 0 : Double(traps.reduce(0, +)) / Double(traps.count)
                out.append("  \(String(size).padding(toLength: 5, withPad: " ", startingAt: 0)) needed \(needed)/\(total)   whole \(whole)/\(rows.count)   sent \(mean.formatted(.number.precision(.fractionLength(1)))) / \(median) / \(sent.last ?? 0)   extras \(trapMean.formatted(.number.precision(.fractionLength(1))))")
            }
            let lows = measured.compactMap { result in result.lowestNeeded.map { ($0, result.name) } }.sorted { $0.0 < $1.0 }.prefix(6)
            if !lows.isEmpty {
                out.append("lowest needed: " + lows.map { "\($0.0.formatted(.number.precision(.fractionLength(2)))) \"\($0.1.prefix(34))\"" }.joined(separator: ", "))
            }
            let latencies = measured.filter { !$0.cached || $0.latencyMs > 0 }.map(\.latencyMs).sorted()
            if !latencies.isEmpty {
                out.append("slowest request per case: median \(latencies[latencies.count / 2]) ms, worst \(latencies.last ?? 0) ms (\(measured.first?.requests ?? 0) requests a case, sent at once)")
            }
        }
        let misses = results.filter { $0.status != .pass }
        if !misses.isEmpty {
            out.append("")
            out.append("misses:")
            for result in misses {
                out.append("  \"\(result.name)\"")
                out.append("      " + result.failures.joined(separator: "; "))
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    public static func text(diff: PickDiff, baseline: String) -> String {
        var out: [String] = []
        out.append("against \(baseline): \(diff.regressions.count) \(diff.regressions.count == 1 ? "regression" : "regressions"), \(diff.fixes.count) \(diff.fixes.count == 1 ? "fix" : "fixes"), \(diff.added.count) new, \(diff.dropped.count) dropped")
        if !diff.regressions.isEmpty {
            out.append("  regressions: " + diff.regressions.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        if !diff.fixes.isEmpty {
            out.append("  fixes: " + diff.fixes.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        if !diff.added.isEmpty { out.append("  new: " + diff.added.map { "\"\($0)\"" }.joined(separator: ", ")) }
        if !diff.dropped.isEmpty { out.append("  dropped: " + diff.dropped.map { "\"\($0)\"" }.joined(separator: ", ")) }
        return out.joined(separator: "\n") + "\n"
    }
}

/// What changed between two runs, by case name; a case not cached on
/// either side is neither a regression nor a fix.
public struct PickDiff: Equatable, Sendable {
    public var regressions: [String] = []
    public var fixes: [String] = []
    public var added: [String] = []
    public var dropped: [String] = []

    public init(regressions: [String] = [], fixes: [String] = [], added: [String] = [], dropped: [String] = []) {
        self.regressions = regressions
        self.fixes = fixes
        self.added = added
        self.dropped = dropped
    }

    public static func compare(baseline: [PickResult], current: [PickResult]) -> PickDiff {
        let before = Dictionary(baseline.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        var diff = PickDiff()
        var seen: Set<String> = []
        for result in current {
            seen.insert(result.name)
            guard let old = before[result.name] else {
                diff.added.append(result.name)
                continue
            }
            guard old.status != .uncached, result.status != .uncached else { continue }
            if old.status == .pass, result.status == .fail { diff.regressions.append(result.name) }
            if old.status == .fail, result.status == .pass { diff.fixes.append(result.name) }
        }
        diff.dropped = baseline.map(\.name).filter { !seen.contains($0) }
        return diff
    }
}
