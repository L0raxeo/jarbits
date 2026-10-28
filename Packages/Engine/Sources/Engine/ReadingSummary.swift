import Foundation

/// What the reading beside the Jev request came back with: the request
/// standing on its own. Rides on the same
/// `DecisionRecord` line as the pick; `original` is what was typed, the
/// record's own `query` is what ran.
public struct ReadingSummary: Codable, Sendable, Equatable {
    public var original: String
    /// The request with its substance isolated; nil when the call gave nothing usable.
    public var query: String?
    public var model: String
    public var latencyMs: Int
    public var usage: AnswerUsage?
    public var outcome: Outcome

    public enum Outcome: Codable, Sendable, Equatable {
        /// The substance differs: the read words ran, and Jev was asked again on them.
        case rewritten
        /// The same substance: the typed words ran.
        case unchanged
        /// The call failed, timed out, or did not parse: the typed words ran.
        case failed(String)
    }

    public init(original: String, query: String? = nil, model: String, latencyMs: Int, usage: AnswerUsage? = nil, outcome: Outcome) {
        self.original = original
        self.query = query
        self.model = model
        self.latencyMs = latencyMs
        self.usage = usage
        self.outcome = outcome
    }

    public var changed: Bool { outcome == .rewritten }
}

/// Whether two forms of a query say the same thing, so a reading that only
/// touched case, punctuation or spacing does not send Jev a second request.
public enum Substance {
    /// Lowercased, diacritics folded, apostrophes gone, other punctuation a
    /// word break, one space between words.
    public static func normalised(_ text: String) -> String {
        Words.key(text)
    }

    public static func differs(_ a: String, _ b: String) -> Bool {
        normalised(a) != normalised(b)
    }
}
