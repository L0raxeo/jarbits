import Foundation

/// A query that asks for the model by name: "ask AI what are some
/// alternatives to Dyson", "can you ask the AI how gingivitis is healed".
/// The ask is explicit, so no router should second-guess it: the question
/// after the opener goes to the answer model as a narrative, with no format
/// question asked and no recency gate, since the user asked for the model's
/// answer knowing what it is. A template, not understanding: leads and one
/// opener come off the front, a connective after it, trailers off the end,
/// and what is left, as typed, is the question.
public struct AnswerQuery: Equatable, Sendable {
    /// What the model is asked: the query's words after the ask, as typed.
    public var question: String

    public init(question: String) {
        self.question = question
    }

    /// Words that may come before the opener, any number of them.
    public static let leads: [String] = SiteQuery.leads

    /// Phrases that hand the question to the model. Longer phrases first.
    public static let openers: [String] = [
        "ask artificial intelligence", "ask the ai", "ask an ai", "ask your ai", "ask ai", "ask chatgpt",
    ]

    /// A phrase that may join the opener to the question, at most one:
    /// "ask AI to tell me what GDP means" asks what GDP means.
    public static let connectives: [String] = ["to tell me", "to explain", "about"]

    /// Words that may close the query without changing it, any number of them.
    public static let trailers: [String] = ["thank you", "for me", "please", "thanks"]

    /// The question, or nil when the query does not name the model, or
    /// names it with nothing to ask.
    public static func parse(_ query: String) -> AnswerQuery? {
        var tokens = QueryTokens(query)
        guard !tokens.isEmpty else { return nil }
        while tokens.stripFront(anyOf: leads) != nil {}
        guard tokens.stripFront(anyOf: openers) != nil else { return nil }
        tokens.stripFront(anyOf: connectives)
        while tokens.stripEnd(anyOf: trailers) != nil {}
        guard !tokens.isEmpty else { return nil }
        return AnswerQuery(question: tokens.text)
    }

    /// What goes to the model: the question after the ask, or the query
    /// itself when it does not name the model.
    public static func question(for query: String) -> String {
        parse(query)?.question ?? query
    }
}
