import Foundation

/// One thing the app knows about the user, in their own words: a
/// preference, an allergy, a name, where they live. Told outright
/// ("remember that I'm allergic to peanuts"), chosen on the sheet, or
/// inferred from what a query said on the way to something else. Facts
/// never expire; `forget` removes one. Every fact goes into every answer
/// and every plan, since there are few.
public struct Fact: Codable, Sendable, Hashable, Identifiable {
    public enum Source: String, Codable, Sendable {
        case told
        case chosen
        case inferred
    }

    public static let currentVersion = 1

    public var id: UUID
    public var text: String
    public var source: Source
    /// The query that made it.
    public var madeBy: String
    /// When it was learned, or last stated again.
    public var date: Date
    public var version: Int

    public init(id: UUID = UUID(), text: String, source: Source, madeBy: String, date: Date = .now) {
        self.id = id
        self.text = text
        self.source = source
        self.madeBy = madeBy
        self.date = date
        version = Self.currentVersion
    }

    enum CodingKeys: String, CodingKey {
        case id, text, source, madeBy, date, version
    }

    /// Tolerant: a line without a source, a maker or a version still reads;
    /// a line without words does not.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .text, in: container, debugDescription: "a fact needs words")
        }
        self.text = text
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = (try? container.decodeIfPresent(String.self, forKey: .source)).flatMap { $0.flatMap(Source.init(rawValue:)) } ?? .inferred
        madeBy = try container.decodeIfPresent(String.self, forKey: .madeBy) ?? ""
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .now
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
    }

    /// The words, folded: what makes two statements the same fact. "I'm
    /// Vegetarian." and "im vegetarian" are one.
    public static func key(_ text: String) -> String {
        Words.key(text)
    }
}

/// How a query touched the facts, for the decision log.
public struct FactSummary: Codable, Sendable, Equatable {
    /// `remembered`, `forgotten`, `declined` (the sheet said keep, or was
    /// swiped away), or `none` (nothing to remember or forget).
    public var action: String
    public var source: Fact.Source?
    public var text: String?
    /// The gate's probability, when it was asked.
    public var remember: Double?
    /// For a forget: how many facts the words pointed at, and how many Jev judged.
    public var candidates: Int?
    public var judged: Int?
    public var latencyMs: Int?

    public init(action: String, source: Fact.Source? = nil, text: String? = nil, remember: Double? = nil, candidates: Int? = nil, judged: Int? = nil, latencyMs: Int? = nil) {
        self.action = action
        self.source = source
        self.text = text
        self.remember = remember
        self.candidates = candidates
        self.judged = judged
        self.latencyMs = latencyMs
    }
}

/// Word matching over the facts, for a forget: the facts holding any of
/// the query's content words come first, best match first, then the
/// newest, so "forget that" alone offers the facts just learned.
public enum FactSearch {
    public static let limit = 5

    /// Words that say "forget" rather than what to forget.
    static let forgetWords: Set<String> = [
        "forget", "forgot", "forgotten", "stop", "remembering", "remembered", "drop", "undo", "remove", "delete",
        "told", "know", "knew", "known", "said", "mentioned", "fact", "facts", "remember", "mind", "note", "noted",
        "anymore", "longer", "never", "wrong", "actually", "correction", "scratch",
    ]

    public static func shortlist(_ facts: [Fact], query: String, now: Date, limit: Int = limit) -> [Fact] {
        let terms = MemorySearch.terms(from: query).filter { !forgetWords.contains($0) }
        let newest = facts.sorted { $0.date > $1.date }
        guard !terms.isEmpty else { return Array(newest.prefix(limit)) }
        let scored = newest.compactMap { fact -> (fact: Fact, hits: Int)? in
            let words = Set(MemorySearch.tokens(of: fact.text))
            let hits = terms.filter { term in words.contains { MemorySearch.close(term, $0) } }.count
            return hits > 0 ? (fact, hits) : nil
        }
        let matched = scored.sorted { $0.hits != $1.hits ? $0.hits > $1.hits : $0.fact.date > $1.fact.date }.map(\.fact)
        let hit = Set(matched.map(\.id))
        let rest = newest.filter { !hit.contains($0.id) }
        return Array((matched + rest).prefix(limit))
    }
}
