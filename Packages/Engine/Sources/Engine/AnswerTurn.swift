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
    public var format: Instinct

    public init(query: String, answer: String, format: Instinct = .narrative) {
        self.query = query
        self.answer = answer
        self.format = format
    }

    /// How the turn is drawn: a line or prose, read off the answer's text,
    /// whatever the format was (2026-11-02).
    public var shape: Shape { Shape.of(answer) }

    enum CodingKeys: String, CodingKey {
        case query, answer, format
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decode(String.self, forKey: .query)
        answer = try container.decode(String.self, forKey: .answer)
        format = try container.decodeIfPresent(Instinct.self, forKey: .format) ?? .narrative
    }
}
