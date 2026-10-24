import Foundation

/// A request for videos to watch: "videos of pele", "show me some cat
/// videos", "You'll pull up some videos of Pele." What goes into Google's
/// video search is the term with the asking gone, as typed. A template,
/// not understanding: corrections and leads come off the front, then one
/// opener, then a quantifier; trailers come off the end; the rest is the
/// term, or the query itself when nothing came off it. Routing is Jev's:
/// a `video` pick is what brings a query here.
public struct VideoQuery: Equatable, Sendable {
    /// What goes into the video search box, as typed.
    public var term: String

    public init(term: String) {
        self.term = term
    }

    public static let corrections: [String] = SearchQuery.corrections
    public static let leads: [String] = SiteQuery.leads

    /// Phrases that ask for videos. Longer phrases first.
    public static let openers: [String] = [
        "i want to watch", "let me watch", "can i watch", "show me", "pull up", "bring up", "find me", "get me", "give me",
        "put on", "play me", "watch", "play", "find",
    ]

    /// What may sit between the opener and the term, at most one.
    public static let quantifiers: [String] = ["a couple of", "a few", "some", "the", "a", "an"]

    public static let trailers: [String] = SearchQuery.trailers

    public static func parse(_ query: String) -> VideoQuery? {
        var tokens = QueryTokens(query)
        guard !tokens.isEmpty else { return nil }
        var stripped = false
        while tokens.stripFront(anyOf: corrections) != nil { stripped = true }
        var led = tokens
        while led.stripFront(anyOf: leads) != nil {}
        if led.stripFront(anyOf: openers) != nil {
            tokens = led
            stripped = true
            if tokens.stripFront(anyOf: quantifiers) != nil { stripped = true }
        }
        while tokens.stripEnd(anyOf: trailers) != nil { stripped = true }
        guard stripped, !tokens.isEmpty else { return nil }
        return VideoQuery(term: tokens.text)
    }

    /// The term to search: the query with the asking gone, or the query
    /// itself when it is already the term.
    public static func term(for query: String) -> String {
        parse(query)?.term ?? ImageQuery.bare(query)
    }
}
