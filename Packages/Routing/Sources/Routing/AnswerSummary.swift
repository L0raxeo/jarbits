import Foundation

/// Gemini prices, pinned here for the ribbon and the decisions report. The
/// log stores tokens, never dollars, so a price change is one edit and old
/// logs re-cost themselves. Source: ai.google.dev pricing, read 2026-10-21,
/// for gemini-3.1-flash-lite.
public enum GeminiPricing {
    public static let inputPerMillionUSD = 0.25
    public static let outputPerMillionUSD = 1.50
}

/// Token counts for one answer, as Gemini reports them.
public struct AnswerUsage: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    /// Billed at the output rate. `minimal` thinking keeps this near zero.
    public var thoughtTokens: Int

    public init(inputTokens: Int, outputTokens: Int, thoughtTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.thoughtTokens = thoughtTokens
    }

    public var costUSD: Double {
        Double(inputTokens) * GeminiPricing.inputPerMillionUSD / 1_000_000
            + Double(outputTokens + thoughtTokens) * GeminiPricing.outputPerMillionUSD / 1_000_000
    }
}

/// What happened when Gemini answered a routed query. Rides on the same
/// `DecisionRecord` line as the routing decision.
public struct AnswerSummary: Codable, Sendable, Equatable {
    public var model: String
    public var format: ResponseFormat
    public var usage: AnswerUsage?
    public var firstTokenMs: Int?
    public var latencyMs: Int?
    public var outcome: Outcome

    public enum Outcome: Codable, Sendable, Equatable {
        /// The answer streamed to the end.
        case completed
        /// A one-line question needed live data; the app showed web results.
        case needsLiveData
        /// The stream failed after some text; the text shown is what arrived.
        case partial(String)
        /// Nothing usable arrived; the app showed web results instead.
        case fellBackToWeb(String)
    }

    public init(
        model: String,
        format: ResponseFormat,
        usage: AnswerUsage? = nil,
        firstTokenMs: Int? = nil,
        latencyMs: Int? = nil,
        outcome: Outcome
    ) {
        self.model = model
        self.format = format
        self.usage = usage
        self.firstTokenMs = firstTokenMs
        self.latencyMs = latencyMs
        self.outcome = outcome
    }
}
