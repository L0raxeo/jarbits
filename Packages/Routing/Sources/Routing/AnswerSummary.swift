import Foundation

/// Gemini prices, pinned here for the ribbon and the decisions report. The
/// log stores tokens and search counts, never dollars, so a price change is
/// one edit and old logs re-cost themselves. Source: ai.google.dev pricing,
/// read 2026-10-21, for gemini-3.1-flash-lite.
public enum GeminiPricing {
    public static let inputPerMillionUSD = 0.25
    public static let outputPerMillionUSD = 1.50
    /// After the free allowance, shared by every Gemini 3+ model on the key.
    public static let searchPerThousandUSD = 14.0
    public static let freeSearchesPerMonth = 5000
}

/// Token and search counts for one answer, as Gemini reports them.
public struct AnswerUsage: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    /// Billed at the output rate. `minimal` thinking keeps this near zero.
    public var thoughtTokens: Int
    /// Google Search calls the model made for this answer.
    public var searches: Int

    public init(inputTokens: Int, outputTokens: Int, thoughtTokens: Int, searches: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.thoughtTokens = thoughtTokens
        self.searches = searches
    }

    /// Token cost only; searches are free until the monthly allowance runs out.
    public var tokenCostUSD: Double {
        Double(inputTokens) * GeminiPricing.inputPerMillionUSD / 1_000_000
            + Double(outputTokens + thoughtTokens) * GeminiPricing.outputPerMillionUSD / 1_000_000
    }
}

/// What happened when Gemini answered a routed query. Rides on the same
/// `DecisionRecord` line as the routing decision.
public struct AnswerSummary: Codable, Sendable, Equatable {
    public var model: String
    public var format: ResponseFormat
    /// The Google queries the model ran, in order. Empty when it answered from memory.
    public var searched: [String]
    public var usage: AnswerUsage?
    public var firstTokenMs: Int?
    public var latencyMs: Int?
    public var outcome: Outcome

    public enum Outcome: Codable, Sendable, Equatable {
        /// The answer streamed to the end.
        case completed
        /// The stream failed after some text; the text shown is what arrived.
        case partial(String)
        /// Nothing usable arrived; the app showed web results instead.
        case fellBackToWeb(String)
    }

    public init(
        model: String,
        format: ResponseFormat,
        searched: [String] = [],
        usage: AnswerUsage? = nil,
        firstTokenMs: Int? = nil,
        latencyMs: Int? = nil,
        outcome: Outcome
    ) {
        self.model = model
        self.format = format
        self.searched = searched
        self.usage = usage
        self.firstTokenMs = firstTokenMs
        self.latencyMs = latencyMs
        self.outcome = outcome
    }
}
