import Foundation

/// What the router decided for one query and why. `format` is what the app
/// acts on, after the confidence gate; `suggested` is Jev's raw pick.
public struct RouteDecision: Codable, Sendable, Equatable {
    public var format: ResponseFormat
    public var suggested: ResponseFormat?
    public var confidence: Double?
    /// Every option's probability, keyed by `ResponseFormat.rawValue`.
    public var probabilities: [String: Double]
    public var model: String?
    public var latencyMs: Int?
    public var inputTokens: Int?
    /// Jev's probability that the right answer may have changed in the last
    /// two years; nil when the question was not asked or not answered.
    public var recency: Double?
    /// Jev's probability that a follow-up continues the narrative on screen;
    /// nil when no narrative was on screen or the question went unanswered.
    public var continuation: Double?
    public var source: Source

    public enum Source: Codable, Sendable, Equatable {
        /// Jev answered and the gate let the answer through.
        case jev
        /// Jev answered below the confidence floor; `format` is the fallback.
        case confidenceFallback
        /// Jev picked a model-answered format with confidence, but `recency`
        /// reached the threshold, so web results are shown instead.
        case recencyFallback
        /// The query was an address, so Jev was not asked.
        case directURL
        /// No API key is configured, so Jev was not asked.
        case noKey
        /// The query continues the narrative on screen (`continuation` reached
        /// the threshold), so the thread grows with a `narrative` turn whatever
        /// the pick was; the pick is kept as `suggested`.
        case continuation
        /// Answered on the device by the named rule (see `LocalAnswers`); no model was asked.
        case local(String)
        /// The request failed; `format` is the fallback.
        case error(String)
    }

    public init(
        format: ResponseFormat,
        suggested: ResponseFormat? = nil,
        confidence: Double? = nil,
        probabilities: [String: Double] = [:],
        model: String? = nil,
        latencyMs: Int? = nil,
        inputTokens: Int? = nil,
        recency: Double? = nil,
        continuation: Double? = nil,
        source: Source
    ) {
        self.format = format
        self.suggested = suggested
        self.confidence = confidence
        self.probabilities = probabilities
        self.model = model
        self.latencyMs = latencyMs
        self.inputTokens = inputTokens
        self.recency = recency
        self.continuation = continuation
        self.source = source
    }

    /// The follow-up carries on the narrative on screen as a new turn.
    public var continuesNarrative: Bool {
        source == .continuation
    }

    public static func directURL() -> RouteDecision {
        RouteDecision(format: .webResults, source: .directURL)
    }

    public static func noKey() -> RouteDecision {
        RouteDecision(format: .webResults, source: .noKey)
    }

    public static func local(_ rule: String, format: ResponseFormat) -> RouteDecision {
        RouteDecision(format: format, source: .local(rule))
    }

    /// The second most likely format, for the debug ribbon.
    public var runnerUp: (format: ResponseFormat, probability: Double)? {
        probabilities
            .compactMap { key, value in ResponseFormat(rawValue: key).map { ($0, value) } }
            .filter { $0.0 != suggested }
            .max { $0.1 < $1.1 }
    }
}
