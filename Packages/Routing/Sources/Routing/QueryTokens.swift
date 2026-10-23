import Foundation

/// The words of a query as typed, each with the key the word lists match
/// by (`SiteQuery.words`: lowercased, accents and punctuation gone). The
/// command parsers that must hand the rest of the query on as typed
/// (`SearchQuery`, `ImageQuery`) strip phrases off this and read `text`;
/// `SiteQuery` works on keys alone and has no use for it.
struct QueryTokens: Equatable {
    struct Token: Equatable {
        var text: String
        var key: String
    }

    private(set) var tokens: [Token]

    init(_ query: String) {
        tokens = query.split(whereSeparator: \.isWhitespace).compactMap { piece in
            let key = SiteQuery.words(String(piece)).joined(separator: " ")
            guard !key.isEmpty else { return nil }   // a stray dash or a lone emoji
            return Token(text: String(piece), key: key)
        }
    }

    var isEmpty: Bool { tokens.isEmpty }
    var count: Int { tokens.count }
    var keys: [String] { tokens.map(\.key) }
    /// What is left, as typed, joined by single spaces.
    var text: String { tokens.map(\.text).joined(separator: " ") }

    /// Removes the first phrase of `phrases` found at the front, never the
    /// whole query, and returns it.
    @discardableResult
    mutating func stripFront(anyOf phrases: [String]) -> String? {
        for phrase in phrases {
            let head = SiteQuery.words(phrase)
            if tokens.count > head.count, Array(keys.prefix(head.count)) == head {
                tokens.removeFirst(head.count)
                return phrase
            }
        }
        return nil
    }

    /// Removes the first phrase of `phrases` found at the end, never the
    /// whole query, and returns it.
    @discardableResult
    mutating func stripEnd(anyOf phrases: [String]) -> String? {
        for phrase in phrases {
            let tail = SiteQuery.words(phrase)
            if tokens.count > tail.count, Array(keys.suffix(tail.count)) == tail {
                tokens.removeLast(tail.count)
                return phrase
            }
        }
        return nil
    }
}
