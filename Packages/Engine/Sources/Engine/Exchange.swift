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
    }

    public var query: String
    public var kind: Kind
    public var title: String?
    public var host: String?
    public var address: String?
    public var text: String?

    public init(query: String, kind: Kind, title: String? = nil, host: String? = nil, address: String? = nil, text: String? = nil) {
        self.query = query
        self.kind = kind
        self.title = title
        self.host = host
        self.address = address
        self.text = text
    }

    public static func answer(query: String, text: String) -> Exchange {
        Exchange(query: query, kind: .answer, text: text)
    }

    public static func page(query: String, title: String, address: URL) -> Exchange {
        Exchange(query: query, kind: .page, title: title, host: address.host(), address: address.absoluteString)
    }

    public static func search(query: String, term: String) -> Exchange {
        Exchange(query: query, kind: .search, text: term)
    }

    public static func recall(query: String, title: String?, titles: [String]) -> Exchange {
        Exchange(query: query, kind: .recall, title: title, text: titles.isEmpty ? nil : titles.joined(separator: "; "))
    }

    public static func site(query: String, name: String, hosts: [String]) -> Exchange {
        Exchange(query: query, kind: .site, title: name, text: hosts.isEmpty ? nil : hosts.joined(separator: ", "))
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
        }
    }
}
