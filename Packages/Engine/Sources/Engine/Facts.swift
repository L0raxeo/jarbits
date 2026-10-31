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
    /// The words this fact replaced, when a later query changed it ("Ana
    /// and I split up" after "Lorcan's wife is Ana"): the history, one step.
    public var previous: String?

    public init(id: UUID = UUID(), text: String, source: Source, madeBy: String, date: Date = .now, previous: String? = nil) {
        self.id = id
        self.text = text
        self.source = source
        self.madeBy = madeBy
        self.date = date
        version = Self.currentVersion
        self.previous = previous
    }

    enum CodingKeys: String, CodingKey {
        case id, text, source, madeBy, date, version, previous
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
        previous = try container.decodeIfPresent(String.self, forKey: .previous)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(source, forKey: .source)
        try container.encode(madeBy, forKey: .madeBy)
        try container.encode(date, forKey: .date)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(previous, forKey: .previous)
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
    /// swiped away), `none` (nothing to remember or forget), or `read`: the
    /// fact reader's own line for a query, with what it found.
    public var action: String
    public var source: Fact.Source?
    public var text: String?
    /// The gate's probability, when it was asked.
    public var remember: Double?
    /// For a forget: how many facts the words pointed at, and how many Jev judged.
    public var candidates: Int?
    public var judged: Int?
    public var latencyMs: Int?
    /// For a reading: how many facts were new, restated, and changed.
    public var found: Int?
    public var restated: Int?
    public var replaced: Int?

    public init(action: String, source: Fact.Source? = nil, text: String? = nil, remember: Double? = nil, candidates: Int? = nil, judged: Int? = nil, latencyMs: Int? = nil, found: Int? = nil, restated: Int? = nil, replaced: Int? = nil) {
        self.action = action
        self.source = source
        self.text = text
        self.remember = remember
        self.candidates = candidates
        self.judged = judged
        self.latencyMs = latencyMs
        self.found = found
        self.restated = restated
        self.replaced = replaced
    }
}

/// Word matching over the facts, for a forget: the facts holding any word
/// of what the forget is about (the extractor's value) come first, best
/// match first, then the newest, so "forget that" alone, about nothing
/// named, offers the facts just learned.
public enum FactSearch {
    public static let limit = 5

    public static func shortlist(_ facts: [Fact], about: String?, now: Date, limit: Int = limit) -> [Fact] {
        let terms = MemorySearch.terms(of: about)
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
