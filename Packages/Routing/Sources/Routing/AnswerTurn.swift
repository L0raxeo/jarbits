import Foundation

/// One exchange in an answer that has become a conversation: what the user
/// asked and what was answered, as the card showed it (with the answer
/// markup), and in which format, so the transcript can show a one-line
/// turn as the short fact it was. The app keeps the turns; Jev sees the
/// last one when a follow-up is routed, and Gemini sees them all when it
/// continues.
public struct AnswerTurn: Hashable, Codable, Sendable {
    public var query: String
    public var answer: String
    /// `narrative` or `one_line`. Turns kept before formats were recorded read as narrative.
    public var format: ResponseFormat

    public init(query: String, answer: String, format: ResponseFormat = .narrative) {
        self.query = query
        self.answer = answer
        self.format = format
    }

    enum CodingKeys: String, CodingKey {
        case query, answer, format
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decode(String.self, forKey: .query)
        answer = try container.decode(String.self, forKey: .answer)
        format = try container.decodeIfPresent(ResponseFormat.self, forKey: .format) ?? .narrative
    }
}
