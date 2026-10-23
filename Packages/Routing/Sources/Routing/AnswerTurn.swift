import Foundation

/// One exchange in a narrative that has become a conversation: what the
/// user asked and what the model answered, as the card showed it (with the
/// answer markup). The app keeps the turns; Jev sees the last one when a
/// follow-up is routed, and Gemini sees them all when it continues.
public struct AnswerTurn: Hashable, Codable, Sendable {
    public var query: String
    public var answer: String

    public init(query: String, answer: String) {
        self.query = query
        self.answer = answer
    }
}
