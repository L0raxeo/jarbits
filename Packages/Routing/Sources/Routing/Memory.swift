import Foundation

/// One thing the user saw: a page, an answer, a picture, a results page.
/// Written to the memories file on the device as the result appears, and
/// found again by `MemorySearch` when a query is routed to `recall`.
public struct MemoryRecord: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A page that loaded, with its address; replays by loading it.
        case page
        /// A narrative answer, with its text; replays from the text.
        case narrative
        /// A one-line answer; replays by asking the query again.
        case oneLine = "one_line"
        /// A picture; replays by asking the query again.
        case image
        /// A results page; replays by asking the query again.
        case search

        /// The kind in words, for the picker.
        public var label: String {
            switch self {
            case .page: "page"
            case .narrative: "answer"
            case .oneLine: "answer"
            case .image: "picture"
            case .search: "search"
            }
        }
    }

    public var id: UUID
    public var date: Date
    public var kind: Kind
    /// The query that produced it, or the query that led to the page.
    public var query: String
    /// The page's title, else the query.
    public var title: String
    /// Pages only.
    public var url: URL?
    /// Narratives only: the answer's markup, as `AnswerMarkup` renders it.
    public var text: String?

    public init(id: UUID = UUID(), date: Date = .now, kind: Kind, query: String, title: String? = nil, url: URL? = nil, text: String? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.query = query
        self.title = title ?? query
        self.url = url
        self.text = text
    }

    /// Two records of the same thing: a page by address, anything else by
    /// kind and query. A repeat within a day refreshes the date.
    public func sameThing(as other: MemoryRecord) -> Bool {
        guard kind == other.kind else { return false }
        if kind == .page { return url == other.url }
        return query.lowercased() == other.query.lowercased()
    }
}

/// How a recall fared, for the decision log: the evidence for whether
/// word matching is enough.
public struct RecallSummary: Codable, Sendable, Equatable {
    public var matches: Int
    /// The kind of the memory shown, when one was.
    public var picked: MemoryRecord.Kind?

    public init(matches: Int, picked: MemoryRecord.Kind? = nil) {
        self.matches = matches
        self.picked = picked
    }
}

/// Word matching over the memories. The query's recall phrasing is dropped
/// ("remember that convo on the dyson pencilvac" → "dyson", "pencilvac");
/// a record matches a term when one of its words contains it, or, for long
/// terms, when its text with the spaces removed does ("pencilvac" against
/// "pencil vac"). Records holding every term win; failing that, records
/// holding any; newest first among equals.
public enum MemorySearch {
    /// Words that say "bring it back" rather than what to bring back.
    static let filler: Set<String> = [
        "where", "wheres", "where's", "my", "remember", "that", "those", "convo", "conversation", "chat",
        "pull", "bring", "up", "again", "go", "back", "the", "a", "an", "to", "from", "earlier",
        "yesterday", "thing", "about", "on", "of", "page", "site", "one", "i", "was", "had", "saw",
        "looked", "at", "open", "show", "me", "find", "get", "it", "and", "with", "for", "in", "you",
        "we", "did", "do", "what", "which", "s",
        // What the user did with it, not what it was.
        "watching", "watched", "watch", "reading", "read", "seen", "see", "looking", "visited",
        "opened", "searched", "asked", "told", "said", "talking", "talked", "mentioned", "earlier",
        "before", "ago", "last", "time", "other", "day", "night", "week", "recently", "just",
        // The kind of thing, which its title rarely says.
        "video", "videos", "clip", "article", "post", "link", "website", "answer", "question",
        "picture", "photo", "image",
    ]

    /// At least this long before a term may match inside joined-up text.
    static let joinedMinimum = 6

    /// The most matches a recall returns.
    public static let limit = 10

    public static func terms(from query: String) -> [String] {
        var seen = Set<String>()
        return tokens(of: query).filter { !filler.contains($0) && $0.count >= 2 && seen.insert($0).inserted }
    }

    public static func matches(_ records: [MemoryRecord], query: String, limit: Int = limit) -> [MemoryRecord] {
        let terms = terms(from: query)
        guard !terms.isEmpty else { return [] }
        let scored = records.compactMap { record -> (record: MemoryRecord, hits: Int)? in
            let ordered = tokens(of: record.haystack)
            let words = Set(ordered)
            let joined = ordered.joined()
            let hits = terms.filter { term in
                words.contains { $0.contains(term) } || (term.count >= joinedMinimum && joined.contains(term))
            }.count
            return hits > 0 ? (record, hits) : nil
        }
        let full = scored.filter { $0.hits == terms.count }
        let chosen = full.isEmpty ? scored : full
        return chosen
            .sorted { $0.hits != $1.hits ? $0.hits > $1.hits : $0.record.date > $1.record.date }
            .prefix(limit)
            .map(\.record)
    }

    static func tokens(of text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

extension MemoryRecord {
    /// Everything a term may match: the query, the title, the page's host
    /// and path, the answer's text.
    var haystack: String {
        var parts = [query, title]
        if let url {
            if let host = url.host() { parts.append(host) }
            parts.append(url.path())
        }
        if let text { parts.append(text) }
        return parts.joined(separator: " ")
    }
}
