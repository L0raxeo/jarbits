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
    /// From before the relevance chain: Jev's probability that a follow-up
    /// continued the answer on screen. Nil on every new line; kept so older
    /// logs decode.
    public var continuation: Double?
    /// Jev's probability that a follow-up rejects the site this app opened
    /// by name; nil when no such site was on screen or the question went
    /// unanswered.
    public var rejection: Double?
    /// Jev's reading of a recall ask, answered in the same request: which
    /// kinds, whether a thing is named, whether a set is wanted. Set only
    /// when `recall` was the pick; absent on older log lines.
    public var recall: RecallIntent?
    /// One probability per exchange sent, oldest first: does the query
    /// depend on it? Nil when no exchange was sent. Logged whole, so a yes
    /// behind a no stays visible.
    public var relevance: [Double]?
    /// How many exchanges, from the newest back, the query depends on: the
    /// walk stops at the first no. Nil when no exchange was sent.
    public var chain: Int?
    /// Jev's reasoning score: 0 direct, 1 a value must be read out of the
    /// words, 2 several steps, a condition or a schedule. Nil when unanswered.
    public var reasoning: Double?
    public var reasoningConfidence: Double?
    public var source: Source

    public enum Source: Codable, Sendable, Equatable {
        /// Jev answered and the gate let the answer through.
        case jev
        /// Jev answered below the confidence floor; `format` is the fallback.
        case confidenceFallback
        /// Jev picked `one_line` or `narrative` below the confidence floor,
        /// but the two together reached `JevRouting.answerMassFloor`: it was
        /// torn between a short and a long answer, so the pick is shown.
        case answerSplit
        /// Jev picked a model-answered format with confidence, but `recency`
        /// reached the threshold, so web results are shown instead.
        case recencyFallback
        /// The query was an address, so Jev was not asked.
        case directURL
        /// No API key is configured, so Jev was not asked.
        case noKey
        /// The relevance chain ends on an answer exchange: the query
        /// continues the answer on screen, so the thread grows with a new
        /// turn whatever the pick was: `one_line` when that was picked with
        /// confidence, `narrative` otherwise; the pick is kept as `suggested`.
        case continuation
        /// The query rejects the site this app opened by name (`rejection`
        /// reached the threshold): `format` is `site` for the same name
        /// again, whatever the pick was; the pick is kept as `suggested`.
        case rejection
        /// Decided on the device by the named rule (see `LocalAnswers`, and
        /// the site book behind `LocalFirstRouter`); no model was asked.
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
        rejection: Double? = nil,
        recall: RecallIntent? = nil,
        relevance: [Double]? = nil,
        chain: Int? = nil,
        reasoning: Double? = nil,
        reasoningConfidence: Double? = nil,
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
        self.rejection = rejection
        self.recall = recall
        self.relevance = relevance
        self.chain = chain
        self.reasoning = reasoning
        self.reasoningConfidence = reasoningConfidence
        self.source = source
    }

    /// The follow-up carries on the answer on screen as a new turn.
    public var continuesThread: Bool {
        source == .continuation
    }

    /// How many exchanges, from the newest back, the query depends on.
    public var chainedCount: Int { chain ?? 0 }

    /// An unsure pick whose reasoning score leans to the top level: the
    /// query wanted sequencing, not a page. Logged for now; advanced
    /// reasoning acts on it once built.
    public var reasoningWanted: Bool {
        source == .confidenceFallback && (reasoning ?? 0) >= EngineRouting.reasoningThreshold
    }

    /// The follow-up says the site on screen is the wrong one.
    public var rejectsSite: Bool {
        source == .rejection
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
