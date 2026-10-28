import Foundation

/// Jev's pick for one query and why. `instinct` is the instinct the app
/// runs; `suggested` is Jev's raw pick, which differs only when the pick
/// was unsure and web results stand in.
public struct Pick: Codable, Sendable, Equatable {
    public var instinct: Instinct
    public var suggested: Instinct?
    public var confidence: Double?
    /// Every option's probability, keyed by `Instinct.rawValue`.
    public var probabilities: [String: Double]
    public var model: String?
    public var latencyMs: Int?
    public var inputTokens: Int?
    /// Jev's probability that the right answer may have changed in the last
    /// two years; nil when the question was not asked or not answered. The
    /// answer instincts act on it; nothing else does.
    public var recency: Double?
    /// Jev's probability that a follow-up rejects the site this app opened
    /// by name; nil when no such site was on screen or the question went
    /// unanswered. The site instinct acts on it.
    public var rejection: Double?
    /// Jev's reading of a recall ask, answered in the same request: which
    /// kinds, whether a thing is named, whether a set is wanted. Set only
    /// when `recall` was the pick.
    public var recall: RecallIntent?
    /// One probability per exchange sent, oldest first: does the query
    /// depend on it? Nil when no exchange was sent. Logged whole, so a yes
    /// behind a no stays visible.
    public var relevance: [Double]?
    /// How many exchanges, from the newest back, the query depends on: the
    /// walk stops at the first no. Nil when no exchange was sent.
    public var chain: Int?
    /// The chain ends on an answer exchange: the query continues the
    /// conversation on screen, so an answer pick grows its thread.
    public var continues: Bool?
    /// Jev's reasoning score: 0 direct, 1 a value must be read out of the
    /// words, 2 several steps, a condition or a schedule. Nil when unanswered.
    public var reasoning: Double?
    public var reasoningConfidence: Double?
    /// The pick's closed-set values Jev read out of the words, by field
    /// name: a choice's option, "true" or "false" for a yes/no. Nil when
    /// the pick declares none or none was stated.
    public var arguments: [String: String]?
    /// Jev's probability that the query states a lasting fact about the
    /// user; nil when the question went unanswered.
    public var remember: Double?
    public var source: Source

    public enum Source: Codable, Sendable, Equatable {
        /// Jev answered with confidence: the pick runs.
        case jev
        /// Jev answered below the confidence floor; `instinct` is web results.
        case confidenceFallback
        /// The query was an address, so it loads as typed: no reading, no Jev.
        case directURL
        /// A step of a plan: the planner chose the instinct, not Jev, so
        /// there is no pick to grade; the plan's own line carries `engine`.
        case plan
        /// No API key is configured, so Jev was not asked; `instinct` is web results.
        case noKey
        /// The request failed; `instinct` is web results.
        case error(String)
    }

    public init(
        instinct: Instinct,
        suggested: Instinct? = nil,
        confidence: Double? = nil,
        probabilities: [String: Double] = [:],
        model: String? = nil,
        latencyMs: Int? = nil,
        inputTokens: Int? = nil,
        recency: Double? = nil,
        rejection: Double? = nil,
        recall: RecallIntent? = nil,
        relevance: [Double]? = nil,
        chain: Int? = nil,
        continues: Bool? = nil,
        reasoning: Double? = nil,
        reasoningConfidence: Double? = nil,
        arguments: [String: String]? = nil,
        remember: Double? = nil,
        source: Source
    ) {
        self.instinct = instinct
        self.suggested = suggested
        self.confidence = confidence
        self.probabilities = probabilities
        self.model = model
        self.latencyMs = latencyMs
        self.inputTokens = inputTokens
        self.recency = recency
        self.rejection = rejection
        self.recall = recall
        self.relevance = relevance
        self.chain = chain
        self.continues = continues
        self.reasoning = reasoning
        self.reasoningConfidence = reasoningConfidence
        self.arguments = arguments
        self.remember = remember
        self.source = source
    }

    /// The query states a lasting fact about the user, by Jev's reading.
    public var statesFact: Bool {
        (remember ?? 0) >= EngineRequest.rememberThreshold
    }

    /// An answer pick whose chain ends on the answer on screen: the thread grows.
    public var continuesThread: Bool {
        instinct.isAnswered && (continues ?? false)
    }

    /// How many exchanges, from the newest back, the query depends on.
    public var chainedCount: Int { chain ?? 0 }

    /// An unsure pick whose reasoning score leans to the top level: the
    /// query wanted sequencing, not a page.
    public var reasoningWanted: Bool {
        source == .confidenceFallback && (reasoning ?? 0) >= EngineRequest.reasoningThreshold
    }

    /// The answer may have gone stale, by Jev's reading: the answer
    /// instincts show web results instead.
    public var recent: Bool {
        (recency ?? 0) >= EngineRequest.recencyThreshold
    }

    /// The query says the site on screen is the wrong one, by Jev's reading.
    public var rejectsSite: Bool {
        (rejection ?? 0) >= EngineRequest.rejectionThreshold
    }

    public static func directURL() -> Pick {
        Pick(instinct: .webResults, source: .directURL)
    }

    public static func noKey() -> Pick {
        Pick(instinct: .webResults, source: .noKey)
    }

    /// The second most likely instinct, for the debug ribbon.
    public var runnerUp: (instinct: Instinct, probability: Double)? {
        probabilities
            .compactMap { key, value in Instinct(rawValue: key).map { ($0, value) } }
            .filter { $0.0 != suggested }
            .max { $0.1 < $1.1 }
    }
}
