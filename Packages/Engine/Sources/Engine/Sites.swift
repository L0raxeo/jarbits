import Foundation

/// A site this route opened and that is still on screen, as the session
/// tells routing: with it Jev is asked whether a follow-up rejects it.
public struct OpenedSite: Hashable, Sendable, Codable {
    /// The name the user asked for, as the book keys it.
    public var name: String
    public var host: String

    public init(name: String, host: String) {
        self.name = name
        self.host = host
    }
}

/// How a `site` pick fared, for the decision log.
public struct SiteSummary: Codable, Sendable, Equatable {
    public var name: String
    /// `opened` (the book knew it), `choices` (candidates shown to learn
    /// from), `results` (no search client, or it failed: the results page
    /// stands in and the first site tapped is learned), `rejected` (the site
    /// on screen was the wrong one and was forgotten).
    public var outcome: String
    /// The host opened, when one was.
    public var host: String?
    /// How many candidates were shown.
    public var candidates: Int?
    /// Why the results page stood in, when it did.
    public var reason: String?
    public var latencyMs: Int?

    public init(name: String, outcome: String, host: String? = nil, candidates: Int? = nil, reason: String? = nil, latencyMs: Int? = nil) {
        self.name = name
        self.outcome = outcome
        self.host = host
        self.candidates = candidates
        self.reason = reason
        self.latencyMs = latencyMs
    }
}
