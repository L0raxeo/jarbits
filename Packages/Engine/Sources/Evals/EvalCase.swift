import Foundation
import Engine

/// One labelled query in the golden set: what was typed, what was on screen,
/// and what the app should do with it. Written by hand, one JSON object per
/// line, in `Evals/engine.jsonl`; a case states intended behaviour, so a
/// case that fails today stays in with a `note` saying why.
/// What a case expects of the engine: the instinct the shortcut runs, or
/// that the pick is unsure and the query is planned. Written in the
/// `instinct` field of a case line as the instinct's name or `planned`.
public enum Expectation: Codable, Equatable, Sendable, CustomStringConvertible {
    case instinct(Instinct)
    case planned

    public static let plannedName = "planned"

    public init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        if name == Self.plannedName { self = .planned; return }
        guard let instinct = Instinct(rawValue: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown expectation \"\(name)\": an instinct, or \(Self.plannedName)"))
        }
        self = .instinct(instinct)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String {
        switch self {
        case let .instinct(instinct): instinct.rawValue
        case .planned: Self.plannedName
        }
    }
}

public struct EvalCase: Codable, Equatable, Sendable {
    public var query: String
    /// The earlier exchanges of the session when the query was typed, oldest first.
    public var exchanges: [Exchange]?
    /// The site this app opened by name and still showed.
    public var opened: OpenedSite?
    /// What the engine should do: run this instinct straight (a sure
    /// pick), or plan the query (an unsure one). The case line's `instinct`.
    public var expected: Expectation
    /// The instinct expected to run straight; nil for a planned case.
    public var instinct: Instinct? {
        if case let .instinct(instinct) = expected { instinct } else { nil }
    }
    /// How many exchanges, from the newest back, the query should depend
    /// on; nil to accept any chain.
    public var chain: Int?
    /// What Jev itself should pick, when that differs from `format`
    /// because the pick should be unsure. Nil to accept any pick.
    public var pick: Instinct?
    /// The path that should get there, as `Pick.Source.kind` names
    /// it (`jev`, `confidenceFallback`, ...); nil to accept any.
    public var source: String?
    /// For a recall: what Jev should read into the ask.
    public var recall: RecallExpectation?
    public var note: String?

    enum CodingKeys: String, CodingKey {
        case query, exchanges, opened, expected = "instinct", chain, pick, source, recall, note
    }

    public init(
        query: String,
        exchanges: [Exchange]? = nil,
        opened: OpenedSite? = nil,
        instinct: Instinct,
        chain: Int? = nil,
        pick: Instinct? = nil,
        source: String? = nil,
        recall: RecallExpectation? = nil,
        note: String? = nil
    ) {
        self.init(query: query, exchanges: exchanges, opened: opened, expected: .instinct(instinct), chain: chain, pick: pick, source: source, recall: recall, note: note)
    }

    public init(
        query: String,
        exchanges: [Exchange]? = nil,
        opened: OpenedSite? = nil,
        expected: Expectation,
        chain: Int? = nil,
        pick: Instinct? = nil,
        source: String? = nil,
        recall: RecallExpectation? = nil,
        note: String? = nil
    ) {
        self.query = query
        self.exchanges = exchanges
        self.opened = opened
        self.expected = expected
        self.chain = chain
        self.pick = pick
        self.source = source
        self.recall = recall
        self.note = note
    }

    /// What a baseline is keyed by: the query, plus the context that makes
    /// the same query a different case. "why?" after "how do you make hot
    /// chocolate"; "no not this one" over zillow.
    public var name: String {
        if let opened { return "\(query) over \(opened.name)" }
        if let last = exchanges?.last { return "\(query) after \"\(last.query)\"" }
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
    case duplicateName(line: Int, name: String)

    public var description: String {
        switch self {
        case let .malformed(line, reason): "line \(line): \(reason)"
        case let .unknownSource(line, source): "line \(line): unknown source \"\(source)\"; one of \(Pick.Source.kinds.joined(separator: ", "))"
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
            if let source = evalCase.source, !Pick.Source.isKind(source) {
                throw EvalSetError.unknownSource(line: number, source: source)
            }
            guard names.insert(evalCase.name).inserted else {
                throw EvalSetError.duplicateName(line: number, name: evalCase.name)
            }
            cases.append(evalCase)
        }
        return cases
    }
}

extension Pick.Source {
    /// The source as one word, for a hand-written file and a readable row:
    /// `jev`, `confidenceFallback`, `error`. (`Codable` nests the enum's
    /// payload, which is unreadable in a case line.)
    public var kind: String {
        switch self {
        case .jev: "jev"
        case .confidenceFallback: "confidenceFallback"
        case .directURL: "directURL"
        case .noKey: "noKey"
        case .plan: "plan"
        case .error: "error"
        }
    }

    public static let kinds = ["jev", "confidenceFallback", "directURL", "noKey", "plan", "error"]

    public static func isKind(_ text: String) -> Bool {
        kinds.contains(text)
    }
}
