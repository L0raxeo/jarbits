import Foundation

/// One earlier query of this session and what it got, as Jev reads it: the
/// words typed and the thing shown for them. The state carries the newest
/// `EngineRequest.maxExchanges` of them, oldest first; one relevance
/// question is asked per exchange, and the instinct chosen gets the ones
/// the query depends on as context. An answer's text goes whole.
public struct Exchange: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// A written answer, Gemini's, the device's or a replayed one; `text` is the answer whole.
        case answer
        /// The web page the layer ended on: `title`, `host`, `address`.
        case page
        /// A results page, video and image results included; `text` is the term in the search box.
        case search
        /// A picture; `text` is the subject asked for, `title` the article found.
                /// A grid of memories; `title` is the grid's heading, `text` the titles shown.
        case recall
        /// The choices card for a site name; `title` is the name, `text` the hosts offered.
        case site
        /// A note of the notebook opened or changed; `title` is its title, `text` its first lines.
        case note
    }

    public var query: String
    public var kind: Kind
    public var title: String?
    public var host: String?
    public var address: String?
    public var text: String?
    /// True for a page or search Jarbits opened on its own screen while
    /// planning, which the user never saw; nil otherwise, so an exchange
    /// the user saw encodes exactly as it always did. Jev is never sent it.
    public var own: Bool?
    /// The note an opened note was (kind `note`), so a handle for the thing
    /// on screen resolves to the notebook's note as the notebook's own
    /// handle does; nil for everything else. Jev is never sent it.
    public var noteID: UUID?
    /// The saved memory an answer shown from the store was, so its handle
    /// brings the record back; nil for everything else. Jev is never sent it.
    public var memoryID: UUID?

    public init(query: String, kind: Kind, title: String? = nil, host: String? = nil, address: String? = nil, text: String? = nil, own: Bool? = nil, noteID: UUID? = nil, memoryID: UUID? = nil) {
        self.query = query
        self.kind = kind
        self.title = title
        self.host = host
        self.address = address
        self.text = text
        self.own = own
        self.noteID = noteID
        self.memoryID = memoryID
    }

    public static func answer(query: String, text: String) -> Exchange {
        Exchange(query: query, kind: .answer, text: text)
    }

    public static func page(query: String, title: String, address: URL, own: Bool? = nil) -> Exchange {
        Exchange(query: query, kind: .page, title: title, host: address.host(), address: address.absoluteString, own: own)
    }

    public static func search(query: String, term: String, own: Bool? = nil) -> Exchange {
        Exchange(query: query, kind: .search, text: term, own: own)
    }

    /// The same exchange as Jev is sent it: without the mark of whose
    /// screen it was on and without the device's ids, so Jev's request
    /// reads as it always did.
    public var forJev: Exchange {
        var copy = self
        copy.own = nil
        copy.noteID = nil
        copy.memoryID = nil
        return copy
    }

    public static func recall(query: String, title: String?, titles: [String]) -> Exchange {
        Exchange(query: query, kind: .recall, title: title, text: titles.isEmpty ? nil : titles.joined(separator: "; "))
    }

    public static func site(query: String, name: String, hosts: [String]) -> Exchange {
        Exchange(query: query, kind: .site, title: name, text: hosts.isEmpty ? nil : hosts.joined(separator: ", "))
    }

    public static func note(query: String, title: String, excerpt: String, noteID: UUID? = nil) -> Exchange {
        Exchange(query: query, kind: .note, title: title, text: excerpt.isEmpty ? nil : excerpt, noteID: noteID)
    }

    /// A conversation's turns as exchanges, oldest first.
    public static func fromTurns(_ turns: [AnswerTurn]) -> [Exchange] {
        turns.map { answer(query: $0.query, answer: $0.answer) }
    }

    private static func answer(query: String, answer: String) -> Exchange {
        .answer(query: query, text: answer)
    }

    /// What the exchange got, in a few words, for a question's instructions.
    public var summary: String {
        switch kind {
        case .answer: "a written answer"
        case .page:
            if let title, let host { "the page \"\(title)\" on \(host)" } else if let title { "the page \"\(title)\"" } else { "a web page" }
        case .search: text.map { "web results for \"\($0)\"" } ?? "web results"
        case .recall: "a grid of earlier memories"
        case .site: title.map { "a choice of sites for \"\($0)\"" } ?? "a choice of sites"
        case .note: title.map { "my note \"\($0)\"" } ?? "a note of my notebook"
        }
    }
}
