import Foundation
import Routing

public enum EvalStatus: String, Codable, Sendable {
    case pass
    case fail
    /// Jev was not asked (no key, or `--no-network`) and the cache had no
    /// answer: neither a pass nor a fail, and left out of a diff.
    case uncached
}

/// One case run: what was expected, what happened, and why it failed if it
/// did. One per line in a results file; the baseline of the next run.
public struct EvalResult: Codable, Equatable, Sendable {
    public var name: String
    public var query: String
    public var expected: ResponseFormat
    public var expectedPick: ResponseFormat?
    public var expectedSource: String?
    public var decision: RouteDecision
    public var localText: String?
    public var searchTerm: String?
    public var imageSubject: String?
    public var siteName: String?
    public var question: String?
    /// Jev's answer came from the cache rather than a request.
    public var cached: Bool
    public var status: EvalStatus
    public var failures: [String]

    public init(_ evalCase: EvalCase, outcome: RouteOutcome, cached: Bool) {
        name = evalCase.name
        query = evalCase.query
        expected = evalCase.format
        expectedPick = evalCase.pick
        expectedSource = evalCase.source
        decision = outcome.decision
        localText = outcome.localText
        searchTerm = outcome.searchTerm
        imageSubject = outcome.imageSubject
        siteName = outcome.siteName
        question = outcome.question
        self.cached = cached
        failures = EvalCheck.failures(evalCase, outcome)
        status = failures.isEmpty ? .pass : .fail
    }

    /// Jev was needed and not available.
    public static func uncached(_ evalCase: EvalCase) -> EvalResult {
        var result = EvalResult(evalCase, outcome: RouteOutcome(query: evalCase.query, decision: RouteDecision(format: .fallback, source: .error("not cached"))), cached: false)
        result.status = .uncached
        result.failures = ["not cached: set TYPESAFE_API_KEY to ask Jev"]
        return result
    }

    public static func parse(_ data: Data) throws -> [EvalResult] {
        try String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try JSONDecoder().decode(EvalResult.self, from: Data($0.utf8)) }
    }

    public static func lines(_ results: [EvalResult]) throws -> Data {
        var out = Data()
        for result in results {
            out.append(try JSONEncoder().encode(result))
            out.append(UInt8(ascii: "\n"))
        }
        return out
    }
}

/// What a case checks, and in which order. Pure, so every rule is testable.
public enum EvalCheck {
    /// Empty means the case passed. The format is what the app shows, so an
    /// expected `web_results` passes whether Jev picked it or fell back;
    /// `source` pins the path. The term, subject and site are only checked
    /// once the format is right: a wrong format explains them already.
    public static func failures(_ evalCase: EvalCase, _ outcome: RouteOutcome) -> [String] {
        let decision = outcome.decision
        switch decision.source {
        case let .error(message): return ["error: \(message)"]
        case .noKey: return ["no key: Jev was not asked"]
        default: break
        }
        var failures: [String] = []
        if decision.format != evalCase.format {
            failures.append("format: expected \(evalCase.format.rawValue), got \(decision.format.rawValue) (\(decision.source.kind))")
        }
        if let pick = evalCase.pick, decision.suggested != pick {
            failures.append("pick: expected \(pick.rawValue), got \(decision.suggested?.rawValue ?? "none")")
        }
        if let expected = evalCase.source, decision.source.kind != expected {
            failures.append("source: expected \(expected), got \(decision.source.kind)")
        }
        guard decision.format == evalCase.format else { return failures }
        if let chain = evalCase.chain, decision.chainedCount != chain {
            let newest = decision.relevance?.last.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "none"
            failures.append("chain: expected \(chain), got \(decision.chainedCount) (newest relevance \(newest))")
        }
        if let term = evalCase.term, outcome.searchTerm != term {
            failures.append("term: expected \"\(term)\", got \(outcome.searchTerm.map { "\"\($0)\"" } ?? "none")")
        }
        if let subject = evalCase.subject, outcome.imageSubject != subject {
            failures.append("subject: expected \"\(subject)\", got \(outcome.imageSubject.map { "\"\($0)\"" } ?? "none")")
        }
        if let site = evalCase.site, outcome.siteName != site {
            failures.append("site: expected \"\(site)\", got \(outcome.siteName.map { "\"\($0)\"" } ?? "none")")
        }
        if let question = evalCase.question, outcome.question != question {
            failures.append("question: expected \"\(question)\", got \(outcome.question.map { "\"\($0)\"" } ?? "none")")
        }
        if let expected = evalCase.recall {
            guard let intent = decision.recall else {
                failures.append("recall: expected an intent, got none")
                return failures
            }
            if let kinds = expected.kinds, Set(kinds) != intent.wanted {
                failures.append("recall kinds: expected [\(kinds.map(\.rawValue).joined(separator: ", "))], got [\(intent.wanted.map(\.rawValue).sorted().joined(separator: ", "))]")
            }
            if let named = expected.named, intent.namesThing != named {
                failures.append("recall named: expected \(named), got \(intent.namesThing) (\(intent.named.formatted(.number.precision(.fractionLength(2)))))")
            }
            if let all = expected.all, intent.wantsAll != all {
                failures.append("recall all: expected \(all), got \(intent.wantsAll) (\(intent.all.formatted(.number.precision(.fractionLength(2)))))")
            }
        }
        return failures
    }
}

/// What changed between two runs, by case name. A case not cached on
/// either side is neither a regression nor a fix.
public struct EvalDiff: Equatable, Sendable {
    public struct Flip: Equatable, Sendable {
        public var name: String
        public var before: EvalResult
        public var after: EvalResult

        public init(name: String, before: EvalResult, after: EvalResult) {
            self.name = name
            self.before = before
            self.after = after
        }
    }

    /// Passed before, fails now.
    public var regressions: [Flip]
    /// Failed before, passes now.
    public var fixes: [Flip]
    /// In the current run only.
    public var added: [String]
    /// In the baseline only.
    public var dropped: [String]

    public init(regressions: [Flip] = [], fixes: [Flip] = [], added: [String] = [], dropped: [String] = []) {
        self.regressions = regressions
        self.fixes = fixes
        self.added = added
        self.dropped = dropped
    }

    public static func compare(baseline: [EvalResult], current: [EvalResult]) -> EvalDiff {
        let before = Dictionary(baseline.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        var diff = EvalDiff()
        var seen: Set<String> = []
        for result in current {
            seen.insert(result.name)
            guard let old = before[result.name] else {
                diff.added.append(result.name)
                continue
            }
            guard old.status != .uncached, result.status != .uncached else { continue }
            if old.status == .pass, result.status == .fail {
                diff.regressions.append(Flip(name: result.name, before: old, after: result))
            } else if old.status == .fail, result.status == .pass {
                diff.fixes.append(Flip(name: result.name, before: old, after: result))
            }
        }
        diff.dropped = baseline.map(\.name).filter { !seen.contains($0) }
        return diff
    }
}
