import Foundation

/// A request for a picture with the asking around the subject: "show me a
/// picture of the eiffel tower", "what does a capybara look like", "photo
/// of the mona lisa please". Wikipedia's search wants the subject alone. A
/// template, not understanding: leads, one opener, articles, one "picture
/// of" phrase and articles again come off the front, trailers off the end,
/// and what is left, as typed, is the subject. Applied only once `image`
/// has been picked, so "show me" here never competes with `SiteQuery`'s.
public struct ImageQuery: Equatable, Sendable {
    /// What is searched: the thing to picture, as typed.
    public var subject: String

    public init(subject: String) {
        self.subject = subject
    }

    /// Words that may come before the opener, any number of them. They only
    /// come off together with an opener or a "picture of" phrase.
    public static let leads: [String] = SiteQuery.leads

    /// How a picture is asked for. Longer phrases first.
    public static let openers: [String] = [
        "show me", "pull up", "bring up", "find me", "find", "get me", "give me", "display",
        "what does", "what do", "how does", "how do",
    ]

    /// Words that may sit before and after the "picture of" phrase.
    public static let articles: [String] = ["a", "an", "the", "some"]

    /// The picture itself, before the subject.
    public static let nounsOf: [String] = [
        "picture of", "photo of", "image of", "pic of", "photograph of",
        "pictures of", "photos of", "images of", "pics of",
    ]

    /// A correction to the picture shown, at the front, any number of them:
    /// "no not that, the dominican flag". Shared with `SearchQuery`.
    public static let corrections: [String] = SearchQuery.corrections

    /// Words that may close the query without changing it, any number of
    /// them. "look like" closes the "what does … look like" form; "i said"
    /// closes a correction ("Dominican flag, I said").
    public static let trailers: [String] = [
        "look like", "looks like", "look", "is what i said", "is what i meant", "like i said", "i said", "i meant",
        "i told you", "please", "for me",
    ]

    /// The subject, or nil when the query is already the subject: nothing
    /// came off it, or everything would have.
    public static func parse(_ query: String) -> ImageQuery? {
        var tokens = QueryTokens(query)
        guard !tokens.isEmpty else { return nil }
        var stripped = false

        while tokens.stripFront(anyOf: corrections) != nil { stripped = true }
        var led = tokens
        while led.stripFront(anyOf: leads) != nil {}
        if led.stripFront(anyOf: openers) != nil {
            tokens = led
            stripped = true
        }
        var probe = tokens
        while probe.stripFront(anyOf: articles) != nil {}
        if probe.stripFront(anyOf: nounsOf) != nil {
            tokens = probe
            stripped = true
        }
        while tokens.stripEnd(anyOf: trailers) != nil { stripped = true }
        if stripped {
            // "show me the eiffel tower", "the dominican flag, i said": the
            // article goes with whatever came off; a bare "the eiffel tower"
            // is left whole.
            while tokens.stripFront(anyOf: articles) != nil {}
        }

        guard stripped, !tokens.isEmpty else { return nil }
        return ImageQuery(subject: tokens.text)
    }

    /// The subject to search: the query with the asking gone, or the query
    /// itself when it is already the subject.
    public static func subject(for query: String) -> String {
        parse(query)?.subject ?? bare(query)
    }

    /// The query as its own subject, without the punctuation dictation
    /// closes a sentence with: "Flag of North Korea." is "Flag of North Korea".
    static func bare(_ query: String) -> String {
        let text = QueryTokens(query).text
        return text.isEmpty ? query : text
    }
}
