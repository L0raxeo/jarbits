import Foundation

/// Where a picture came from: Wikipedia first, free and with a licence on
/// the article; Brave's image search behind it, for a subject Wikipedia has
/// no article on.
public enum ImageSource: String, Codable, Sendable, Equatable, CaseIterable {
    case wikipedia
    case brave
}

/// What happened when an image plan was filled: from Wikipedia, from Brave
/// behind it, or from neither. Rides on the same `DecisionRecord` line as
/// the routing decision.
public struct ImageSummary: Codable, Sendable, Equatable {
    /// The article, or the Brave result's title, whose picture was shown.
    public var article: String?
    /// How many candidates had a usable picture.
    public var candidates: Int
    /// From the query to the first picture decoded.
    public var latencyMs: Int?
    /// Which source answered; absent on a fallback, and on lines written
    /// before Brave was a source.
    public var source: ImageSource?
    public var outcome: Outcome

    public enum Outcome: Codable, Sendable, Equatable {
        /// A picture was shown, with this many alternates under it.
        case shown(alternates: Int)
        /// No picture; the app showed web results instead.
        case fellBackToWeb(String)
    }

    public init(article: String? = nil, candidates: Int, latencyMs: Int? = nil, source: ImageSource? = nil, outcome: Outcome) {
        self.article = article
        self.candidates = candidates
        self.latencyMs = latencyMs
        self.source = source
        self.outcome = outcome
    }
}
