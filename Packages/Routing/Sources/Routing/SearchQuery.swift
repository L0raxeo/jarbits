import Foundation

/// A query that names the search itself: "google steve jobs", "search for
/// flights to lima", "look up the eiffel tower". The verb is what gets the
/// query to web results; it should not go into the search box with the
/// term. A template, not understanding: leads and one opener come off the
/// front, trailers off the end, and what is left, as typed, is the term.
///
/// The verbs in `openers` only ever mean "search", so a query led by one is
/// web results with no model asked (`LocalFirstRouter`). "google" is also a
/// company ("google stock", "google maps"), so it comes off only once Jev
/// has picked web results, and never when a Google product follows it.
public struct SearchQuery: Equatable, Sendable {
    /// What goes into the search box: the query's words after the command, as typed.
    public var term: String
    /// One of `openers` led the query: route it to web results without a model.
    public var isCommand: Bool

    public init(term: String, isCommand: Bool) {
        self.term = term
        self.isCommand = isCommand
    }

    /// Words that may come before the opener, any number of them. They only
    /// come off together with an opener.
    public static let leads: [String] = SiteQuery.leads

    /// Verbs that only ever ask for a search. Longer phrases first.
    public static let openers: [String] = [
        "search google for", "search the web for", "search the internet for", "do a google search for",
        "do a web search for", "do a search for", "google search for", "web search for", "web search",
        "search for", "search up", "look up", "lookup",
    ]

    /// "google" as a verb, stripped only after a web pick.
    public static let brandOpener = "google"

    /// Words after "google" that make it the company's name, not a verb:
    /// "google maps", "google docs", "google stock" are searched whole.
    public static let googleProducts: [String] = [
        "maps", "docs", "drive", "translate", "photos", "calendar", "flights", "sheets", "slides", "meet",
        "play", "pixel", "chrome", "gemini", "cloud", "home", "nest", "pay", "wallet", "ads", "analytics",
        "news", "scholar", "classroom", "keep", "fi", "one", "store", "stock", "shares", "earnings",
        "account", "assistant", "lens", "tv", "fiber", "workspace", "search", "io", "glass", "voice",
    ]

    /// A correction to what the app did last, at the front, any number of
    /// them: "no not that, steve jobs". They come off with or without an
    /// opener. A bare "no" is not one: "no man's sky" is a game.
    public static let corrections: [String] = [
        "no not that one", "no not that", "no not this", "no i said", "no i meant", "not that one", "not that",
        "i said", "i meant", "i told you", "like i said",
    ]

    /// Words that may close the query without changing it, any number of
    /// them, with or without an opener: "steve jobs, I said".
    public static let trailers: [String] = [
        "is what i said", "is what i meant", "like i said", "i said", "i meant", "i told you",
        "on google", "for me", "please",
    ]

    /// The command and its term, or nil when the query names no search:
    /// nothing came off it, or everything would have.
    public static func parse(_ query: String) -> SearchQuery? {
        var tokens = QueryTokens(query)
        guard !tokens.isEmpty else { return nil }
        var stripped = false
        var isCommand = false

        while tokens.stripFront(anyOf: corrections) != nil { stripped = true }
        var led = tokens
        while led.stripFront(anyOf: leads) != nil {}
        if led.stripFront(anyOf: openers) != nil {
            tokens = led
            stripped = true
            isCommand = true
        } else if led.count > 1, led.keys[0] == brandOpener, !googleProducts.contains(led.keys[1]) {
            led.stripFront(anyOf: [brandOpener])
            tokens = led
            stripped = true
        }
        while tokens.stripEnd(anyOf: trailers) != nil { stripped = true }

        guard stripped, !tokens.isEmpty else { return nil }
        return SearchQuery(term: tokens.text, isCommand: isCommand)
    }

    /// The term to search: the query with its command gone, or the query
    /// itself when it names no search.
    public static func term(for query: String) -> String {
        parse(query)?.term ?? ImageQuery.bare(query)
    }
}
