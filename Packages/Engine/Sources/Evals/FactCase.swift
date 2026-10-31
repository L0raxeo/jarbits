import Foundation
import Answers
import Engine

/// One case of the fact reader's set: a request, the facts already known,
/// and the findings expected, as a set: each expected finding must match
/// one returned by kind, by the known fact's number, and by every word it
/// must contain; more findings than expected fail the case unless it says
/// `allowMore`.
public struct FactCase: Codable, Equatable, Sendable {
    public struct Expected: Codable, Equatable, Sendable {
        public var kind: FactReader.Finding.Kind
        public var of: Int?
        /// Words the finding's text must contain, case aside.
        public var contains: [String]?

        public init(kind: FactReader.Finding.Kind, of: Int? = nil, contains: [String]? = nil) {
            self.kind = kind
            self.of = of
            self.contains = contains
        }

        public func matches(_ finding: FactReader.Finding) -> Bool {
            guard finding.kind == kind, finding.of == of else { return false }
            let text = finding.text.lowercased()
            return (contains ?? []).allSatisfy { text.contains($0.lowercased()) }
        }
    }

    public var query: String
    public var exchanges: [Exchange]?
    public var known: [String]?
    public var expect: [Expected]
    public var allowMore: Bool?
    public var note: String?

    public init(query: String, exchanges: [Exchange]? = nil, known: [String]? = nil, expect: [Expected], allowMore: Bool? = nil, note: String? = nil) {
        self.query = query
        self.exchanges = exchanges
        self.known = known
        self.expect = expect
        self.allowMore = allowMore
        self.note = note
    }

    public var name: String {
        var name = query
        if let known, !known.isEmpty { name += " knowing \(known.count)" }
        if let last = exchanges?.last { name += " after \"\(last.query)\"" }
        return name
    }
}

extension FactReader.Finding.Kind: Codable {}

public enum FactSet {
    public static func parse(_ data: Data) throws -> [FactCase] {
        var cases: [FactCase] = []
        var names: Set<String> = []
        let decoder = JSONDecoder()
        for (index, line) in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let number = index + 1
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let factCase: FactCase
            do {
                factCase = try decoder.decode(FactCase.self, from: Data(line.utf8))
            } catch {
                throw EvalSetError.malformed(line: number, reason: String(describing: error))
            }
            guard names.insert(factCase.name).inserted else { throw EvalSetError.duplicateName(line: number, name: factCase.name) }
            cases.append(factCase)
        }
        return cases
    }
}

public enum FactCheck {
    /// Every expected finding matched by a distinct returned one, the
    /// pairing chosen so the most are matched (a finding that fits two
    /// expectations goes to the one nothing else fits), and no unmatched
    /// return unless the case allows more.
    public static func failures(_ factCase: FactCase, findings: [FactReader.Finding]) -> [String] {
        let pairing = bestPairing(factCase.expect, findings)
        var failures: [String] = []
        for (index, expected) in factCase.expect.enumerated() where pairing[index] == nil {
            let words = (expected.contains ?? []).map { "\"\($0)\"" }.joined(separator: ", ")
            failures.append("expected a \(expected.kind.rawValue) fact\(expected.of.map { " of \($0)" } ?? "")\(words.isEmpty ? "" : " containing \(words)"), none matched")
        }
        let used = Set(pairing.compactMap { $0 })
        let left = findings.indices.filter { !used.contains($0) }.map { findings[$0] }
        if !left.isEmpty, factCase.allowMore != true {
            failures.append("unexpected: " + left.map { "\($0.kind.rawValue)\($0.of.map { " of \($0)" } ?? "") \"\($0.text)\"" }.joined(separator: "; "))
        }
        return failures
    }

    /// For each expectation, the index of the finding paired with it, or
    /// nil: the pairing with the most matches, found by trying each in turn
    /// (the sets are a handful long).
    static func bestPairing(_ expected: [FactCase.Expected], _ findings: [FactReader.Finding]) -> [Int?] {
        func search(_ index: Int, _ used: Set<Int>) -> [Int?] {
            guard index < expected.count else { return [] }
            var best: [Int?] = [nil] + search(index + 1, used)
            for (i, finding) in findings.enumerated() where !used.contains(i) && expected[index].matches(finding) {
                let candidate: [Int?] = [i] + search(index + 1, used.union([i]))
                if candidate.compactMap({ $0 }).count > best.compactMap({ $0 }).count { best = candidate }
            }
            return best
        }
        return search(0, [])
    }
}

public struct FactResult: Codable, Equatable, Sendable {
    public struct Found: Codable, Equatable, Sendable {
        public var text: String
        public var kind: String
        public var of: Int?
    }

    public var name: String
    public var query: String
    public var findings: [Found]
    public var cached: Bool
    public var latencyMs: Int
    public var status: EvalStatus
    public var failures: [String]
}

/// Runs the fact reader's cases: from the cache when the request bytes
/// are known, else one metered call, with the example persona and date so
/// the bytes are stable.
public struct FactRunner: Sendable {
    public var client: GeminiClient?
    public var cache: PlanCache
    public var timeout: Duration

    public init(client: GeminiClient?, cache: PlanCache, timeout: Duration = FactReader.timeout) {
        self.client = client
        self.cache = cache
        self.timeout = timeout
    }

    public static func request(for factCase: FactCase, model: String = FactReader.model) -> InteractionRequest {
        FactReader.request(query: factCase.query, exchanges: Array((factCase.exchanges ?? []).suffix(FactReader.exchangesGiven)), known: factCase.known ?? [], persona: .example, model: model, now: AnswerContext.example.now)
    }

    public func run(_ cases: [FactCase]) async -> [FactResult] {
        var results: [FactResult] = []
        for factCase in cases { results.append(await run(factCase)) }
        return results
    }

    public func run(_ factCase: FactCase) async -> FactResult {
        let request = Self.request(for: factCase, model: client?.model ?? FactReader.model)
        func result(_ findings: [FactReader.Finding], cached: Bool, latencyMs: Int, status: EvalStatus? = nil, failures: [String]? = nil) -> FactResult {
            let found = failures ?? FactCheck.failures(factCase, findings: findings)
            return FactResult(name: factCase.name, query: factCase.query, findings: findings.map { .init(text: $0.text, kind: $0.kind.rawValue, of: $0.of) }, cached: cached, latencyMs: latencyMs, status: status ?? (found.isEmpty ? .pass : .fail), failures: found)
        }
        guard let key = try? PlanCache.key(for: request) else {
            return result([], cached: false, latencyMs: 0, status: .fail, failures: ["could not encode the request"])
        }
        let data: Data
        let latency: Int
        let cached: Bool
        if let entry = cache.entry(for: key) {
            data = entry.response
            latency = entry.latencyMs
            cached = true
        } else {
            guard let client else {
                return result([], cached: false, latencyMs: 0, status: .uncached, failures: ["not cached: set GEMINI_API_KEY to ask the reader"])
            }
            let clock = ContinuousClock()
            let start = clock.now
            do {
                data = try await client.send(request, timeout: timeout)
            } catch {
                return result([], cached: false, latencyMs: Int((clock.now - start) / .milliseconds(1)), status: .fail, failures: ["error: \(error.summary)"])
            }
            latency = Int((clock.now - start) / .milliseconds(1))
            cached = false
            try? cache.store(key: key, request: request, query: factCase.query, response: data, latencyMs: latency)
        }
        let interaction: Interaction
        do {
            interaction = try InteractionResponse.parse(data)
        } catch {
            return result([], cached: cached, latencyMs: latency, status: .fail, failures: ["error: \(error.summary)"])
        }
        guard interaction.usable else {
            return result([], cached: cached, latencyMs: latency, status: .fail, failures: ["error: status \(interaction.status)"])
        }
        guard let findings = FactReader.findings(in: interaction.text.trimmingCharacters(in: .whitespacesAndNewlines), known: (factCase.known ?? []).count) else {
            return result([], cached: cached, latencyMs: latency, status: .fail, failures: ["not a list: \(interaction.text.prefix(80))"])
        }
        return result(findings, cached: cached, latencyMs: latency)
    }
}

public enum FactReport {
    public static func text(results: [FactResult], file: String, model: String) -> String {
        var out: [String] = []
        let passed = results.filter { $0.status == .pass }.count
        let failed = results.filter { $0.status == .fail }.count
        let uncached = results.filter { $0.status == .uncached }.count
        let fromCache = results.filter(\.cached).count
        let asked = results.count - fromCache - uncached
        out.append("facts \(file): \(results.count) cases, \(passed) passed, \(failed) failed\(uncached > 0 ? ", \(uncached) not cached" : "") (\(model); \(fromCache) from cache, \(asked) asked the reader)")
        let misses = results.filter { $0.status != .pass }
        if !misses.isEmpty {
            out.append("")
            out.append("misses:")
            for result in misses {
                out.append("  \"\(result.name)\"")
                out.append("      " + result.failures.joined(separator: "; "))
                if !result.findings.isEmpty {
                    out.append("      found: " + result.findings.map { "\($0.kind)\($0.of.map { " of \($0)" } ?? "") \"\($0.text)\"" }.joined(separator: "; "))
                }
            }
        }
        return out.joined(separator: "\n") + "\n"
    }
}
