import Foundation

/// What happened when an image plan was filled from Wikipedia. Rides on the
/// same `DecisionRecord` line as the routing decision.
public struct ImageSummary: Codable, Sendable, Equatable {
    /// The article whose picture was shown.
    public var article: String?
    /// How many candidates had a usable picture.
    public var candidates: Int
    /// From the query to the first picture decoded.
    public var latencyMs: Int?
    public var outcome: Outcome

    public enum Outcome: Codable, Sendable, Equatable {
        /// A picture was shown, with this many alternates under it.
        case shown(alternates: Int)
        /// No picture; the app showed web results instead.
        case fellBackToWeb(String)
    }

    public init(article: String? = nil, candidates: Int, latencyMs: Int? = nil, outcome: Outcome) {
        self.article = article
        self.candidates = candidates
        self.latencyMs = latencyMs
        self.outcome = outcome
    }
}
