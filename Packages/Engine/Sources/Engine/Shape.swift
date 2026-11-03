import Foundation

/// The shape an answer turned out to have, read off its text once the
/// model has decided it (2026-11-02; before, Jev's one_line or narrative
/// pick decided it for him): a line, one row of at most twelve words, or
/// prose. The screen follows the shape, not the pick: a line is shown
/// large and bare, prose as a card.
public enum Shape: String, Codable, Sendable {
    case line
    case prose

    /// A line is at most this many words.
    public static let lineWords = 12

    /// Of a finished text: one line of at most `lineWords` words.
    public static func of(_ text: String) -> Shape {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return .prose }
        return words(trimmed).count <= lineWords ? .line : .prose
    }

    /// While the text streams: a line until a second row or a thirteenth
    /// word arrives, then prose, never back, since the text only grows.
    public static func streaming(_ text: String) -> Shape {
        text.contains("\n") || words(text).count > lineWords ? .prose : .line
    }

    /// The words, the emphasis markers left out of the count.
    static func words(_ text: String) -> [Substring] {
        text.replacingOccurrences(of: "==", with: "").replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .split(whereSeparator: \.isWhitespace)
    }
}
