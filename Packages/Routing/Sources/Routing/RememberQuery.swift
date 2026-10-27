import Foundation

/// A query that asks the app to keep something in mind: "remember that I'm
/// allergic to peanuts", "keep in mind I'm vegetarian", "don't forget my
/// wife's name is Ana". A template, not understanding: leads and one
/// opener come off the front, trailers off the end, and what is left, as
/// typed, is the fact. Read only after the engine has decided the query
/// is a remember: "remember that convo on the dyson pencilvac" parses too,
/// and it is a recall.
public struct RememberQuery: Equatable, Sendable {
    /// The fact, in the user's words.
    public var fact: String

    public init(fact: String) {
        self.fact = fact
    }

    /// Words that may come before the opener, any number of them.
    public static let leads: [String] = SiteQuery.leads

    /// Phrases that hand the fact over. Longer phrases first.
    public static let openers: [String] = [
        "please remember that", "remember for me that", "keep in mind that", "bear in mind that",
        "don't forget that", "dont forget that", "do not forget that", "make a note that", "note that",
        "for future reference", "please remember", "remember that", "keep in mind", "bear in mind",
        "don't forget", "dont forget", "do not forget", "make a note", "note down", "remember",
    ]

    /// Words that may close the query without changing it, any number of them.
    public static let trailers: [String] = ["thank you", "for me", "please", "thanks", "okay", "ok"]

    /// The fact, or nil when the query does not ask to remember, or asks
    /// with nothing to remember.
    public static func parse(_ query: String) -> RememberQuery? {
        var tokens = QueryTokens(query)
        guard !tokens.isEmpty else { return nil }
        while tokens.stripFront(anyOf: leads) != nil {}
        guard tokens.stripFront(anyOf: openers) != nil else { return nil }
        while tokens.stripEnd(anyOf: trailers) != nil {}
        guard !tokens.isEmpty else { return nil }
        return RememberQuery(fact: tokens.text)
    }
}
