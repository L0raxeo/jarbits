import Foundation

/// What happened when a model was asked to read an instinct's free-form
/// values out of the words. Rides on the same `DecisionRecord` line as the
/// routing decision.
public struct ExtractionSummary: Codable, Sendable, Equatable {
    public var model: String
    public var latencyMs: Int
    public var usage: AnswerUsage?
    /// The fields a value came back for, by name.
    public var fields: [String]
    public var outcome: Outcome

    public enum Outcome: Codable, Sendable, Equatable {
        /// At least one value was read.
        case extracted
        /// The reply parsed but held no value.
        case empty
        /// The call failed, timed out, or did not parse.
        case failed(String)
    }

    public init(model: String, latencyMs: Int, usage: AnswerUsage? = nil, fields: [String] = [], outcome: Outcome) {
        self.model = model
        self.latencyMs = latencyMs
        self.usage = usage
        self.fields = fields
        self.outcome = outcome
    }
}
