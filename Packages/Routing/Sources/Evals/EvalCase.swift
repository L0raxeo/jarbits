import Foundation
import Routing

/// One labelled query in the golden set: what was typed, what was on screen,
/// and what the app should do with it. Written by hand, one JSON object per
/// line, in `Evals/routing.jsonl`; a case states intended behaviour, so a
/// case that fails today stays in with a `note` saying why.
public struct EvalCase: Codable, Equatable, Sendable {
    public var query: String
    /// The conversation on screen when the query was typed, oldest first.
    public var thread: [AnswerTurn]?
    /// The site this app opened by name and still showed.
    public var opened: OpenedSite?
    /// The format the app should act on, after every gate.
    public var format: ResponseFormat
    /// What Jev itself should pick, when that differs from `format` because
    /// a gate steps in: a narrative about a recent event is picked as
    /// narrative and shown as web results. Nil to accept any pick.
    public var pick: ResponseFormat?
    /// The path that should get there, as `RouteDecision.Source.kind` names
    /// it (`local:search`, `jev`, `confidenceFallback`, ...); nil to accept any.
    public var source: String?
    /// For web results: what should go into the search box.
    public var term: String?
    /// For an image: what Wikipedia should be asked for.
    public var subject: String?
    /// For a site: the name looked up in the book.
    public var site: String?
    /// For an answer: what the model should be asked.
    public var question: String?
    /// For a recall: what Jev should read into the ask.
    public var recall: RecallExpectation?
    public var note: String?

    public init(
        query: String,
        thread: [AnswerTurn]? = nil,
        opened: OpenedSite? = nil,
        format: ResponseFormat,
        pick: ResponseFormat? = nil,
        source: String? = nil,
        term: String? = nil,
        subject: String? = nil,
        site: String? = nil,
        question: String? = nil,
        recall: RecallExpectation? = nil,
        note: String? = nil
    ) {
        self.query = query
        self.thread = thread
        self.opened = opened
        self.format = format
        self.pick = pick
        self.source = source
        self.term = term
        self.subject = subject
        self.site = site
        self.question = question
        self.recall = recall
        self.note = note
    }

    /// What a baseline is keyed by: the query, plus the context that makes
    /// the same query a different case. "why?" after "how do you make hot
    /// chocolate"; "no not this one" over zillow.
    public var name: String {
        if let last = thread?.last { return "\(query) after \"\(last.query)\"" }
        if let opened { return "\(query) over \(opened.name)" }
        return query
    }
}

/// What Jev should read into a recall ask. A nil field accepts anything;
/// `kinds: []` expects no kind.
public struct RecallExpectation: Codable, Equatable, Sendable {
    public var kinds: [RecallIntent.Kind]?
    public var named: Bool?
    public var all: Bool?

    public init(kinds: [RecallIntent.Kind]? = nil, named: Bool? = nil, all: Bool? = nil) {
        self.kinds = kinds
        self.named = named
        self.all = all
    }
}

public enum EvalSetError: Error, CustomStringConvertible, Equatable {
    case malformed(line: Int, reason: String)
    case unknownSource(line: Int, source: String)
    case threadAndOpened(line: Int)
    case duplicateName(line: Int, name: String)

    public var description: String {
        switch self {
        case let .malformed(line, reason): "line \(line): \(reason)"
        case let .unknownSource(line, source): "line \(line): unknown source \"\(source)\"; one of \(RouteDecision.Source.kinds.joined(separator: ", ")) or local:<rule>"
        case let .threadAndOpened(line): "line \(line): a case has a thread or an opened site, never both (an answer on screen means no page is)"
        case let .duplicateName(line, name): "line \(line): \"\(name)\" appears twice; a baseline is keyed by the name"
        }
    }
}

public enum EvalSet {
    /// One JSON object per line; blank lines are skipped. Throws on the
    /// first problem, with the line number.
    public static func parse(_ data: Data) throws -> [EvalCase] {
        var cases: [EvalCase] = []
        var names: Set<String> = []
        let decoder = JSONDecoder()
        for (index, line) in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let number = index + 1
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let evalCase: EvalCase
            do {
                evalCase = try decoder.decode(EvalCase.self, from: Data(line.utf8))
            } catch {
                throw EvalSetError.malformed(line: number, reason: String(describing: error))
            }
            if let source = evalCase.source, !RouteDecision.Source.isKind(source) {
                throw EvalSetError.unknownSource(line: number, source: source)
            }
            if evalCase.thread?.isEmpty == false, evalCase.opened != nil {
                throw EvalSetError.threadAndOpened(line: number)
            }
            guard names.insert(evalCase.name).inserted else {
                throw EvalSetError.duplicateName(line: number, name: evalCase.name)
            }
            cases.append(evalCase)
        }
        return cases
    }
}

extension RouteDecision.Source {
    /// The source as one word, for a hand-written file and a readable row:
    /// `local:time`, `jev`, `confidenceFallback`, `error`. (`Codable` nests
    /// the enum's payload, which is unreadable in a case line.)
    public var kind: String {
        switch self {
        case .jev: "jev"
        case .confidenceFallback: "confidenceFallback"
        case .recencyFallback: "recencyFallback"
        case .directURL: "directURL"
        case .noKey: "noKey"
        case .continuation: "continuation"
        case .rejection: "rejection"
        case let .local(rule): "local:\(rule)"
        case .error: "error"
        }
    }

    /// Every kind without a payload; a local rule is `local:<rule>`.
    public static let kinds = ["jev", "confidenceFallback", "recencyFallback", "directURL", "noKey", "continuation", "rejection", "error"]

    public static func isKind(_ text: String) -> Bool {
        kinds.contains(text) || (text.hasPrefix("local:") && text.count > "local:".count)
    }
}
