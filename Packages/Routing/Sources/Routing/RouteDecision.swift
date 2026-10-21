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
    public var source: Source

    public enum Source: Codable, Sendable, Equatable {
        /// Jev answered and the gate let the answer through.
        case jev
        /// Jev answered below the confidence floor; `format` is the fallback.
        case confidenceFallback
        /// The query was an address, so Jev was not asked.
        case directURL
        /// No API key is configured, so Jev was not asked.
        case noKey
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
        source: Source
    ) {
        self.format = format
        self.suggested = suggested
        self.confidence = confidence
        self.probabilities = probabilities
        self.model = model
        self.latencyMs = latencyMs
        self.inputTokens = inputTokens
        self.source = source
    }

    public static func directURL() -> RouteDecision {
        RouteDecision(format: .webResults, source: .directURL)
    }

    public static func noKey() -> RouteDecision {
        RouteDecision(format: .webResults, source: .noKey)
    }

    /// The second most likely format, for the debug ribbon.
    public var runnerUp: (format: ResponseFormat, probability: Double)? {
        probabilities
            .compactMap { key, value in ResponseFormat(rawValue: key).map { ($0, value) } }
            .filter { $0.0 != suggested }
            .max { $0.1 < $1.1 }
    }
}
