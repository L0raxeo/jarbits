import Foundation

/// A thing the planner can point at: an exchange of this session, or a
/// memory. The device knows each one exactly (a page's address, a search's
/// term, an answer's text, a memory's record); the planner only ever names
/// it by a handle from its listing, and the device swaps the handle for the
/// thing before a step runs. No model carries an address.
public enum Thing: Sendable, Equatable {
    case exchange(Exchange)
    case memory(MemoryRecord)
}

/// What a thing is, exactly, for an instinct to act on.
public struct Reference: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case page, search, answer, picture, recall, site, action
    }

    public var kind: Kind
    public var title: String
    public var address: URL?
    public var term: String?
    public var text: String?
    public var memoryID: UUID?

    public init(kind: Kind, title: String, address: URL? = nil, term: String? = nil, text: String? = nil, memoryID: UUID? = nil) {
        self.kind = kind
        self.title = title
        self.address = address
        self.term = term
        self.text = text
        self.memoryID = memoryID
    }

    public init(_ thing: Thing) {
        switch thing {
        case let .exchange(exchange):
            switch exchange.kind {
            case .page:
                self.init(kind: .page, title: exchange.title ?? exchange.query, address: exchange.address.flatMap(URL.init(string:)))
            case .search:
                self.init(kind: .search, title: exchange.text ?? exchange.query, term: exchange.text ?? exchange.query)
            case .answer:
                self.init(kind: .answer, title: exchange.query, text: exchange.text)
            case .recall:
                self.init(kind: .recall, title: exchange.title ?? exchange.query, text: exchange.text)
            case .site:
                self.init(kind: .site, title: exchange.title ?? exchange.query, text: exchange.text)
            }
        case let .memory(record):
            let kind: Kind = switch record.kind {
            case .page: .page
            case .search: .search
            case .narrative, .oneLine: .answer
            case .image: .picture
            case .action: .action
            }
            self.init(kind: kind, title: record.title, address: record.url, term: record.kind == .search ? record.query : nil, text: record.text, memoryID: record.id)
        }
    }

    /// The thing as an exchange, for an answer's context block.
    public func asExchange(query: String) -> Exchange {
        switch kind {
        case .page:
            if let address { return .page(query: query, title: title, address: address) }
            return Exchange(query: query, kind: .page, title: title)
        case .search: return .search(query: query, term: term ?? title)
        case .answer, .action: return .answer(query: title, text: text ?? "")
        case .picture: return Exchange(query: query, kind: .search, text: title)
        case .recall: return .recall(query: query, title: title, titles: [])
        case .site: return .site(query: query, name: title, hosts: [])
        }
    }
}

extension Exchange {
    /// One exchange as a line of a model's context: what was done and got.
    public var described: String {
        switch kind {
        case .answer: "Asked \"\(query)\" and got: \(text ?? "")"
        case .page:
            if let title, let host { "Read \"\(title)\" (\(host))" }
            else if let title { "Read \"\(title)\"" }
            else { "Read a page for \"\(query)\"" }
        case .search: "Searched \"\(text ?? query)\""
        case .recall: "Looked through earlier memories for \"\(query)\""
        case .site:
            if let text { "Chose among sites for \"\(title ?? query)\": \(text)" }
            else { "Chose among sites for \"\(title ?? query)\"" }
        }
    }
}

/// The handles of one plan: `p1, p2…` for the exchanges the query depends
/// on (oldest first), `m1, m2…` for the memories shown, and more memories
/// minted by a step's result. Nothing is renumbered, and a table never
/// outlives its plan.
public struct ThingTable: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let handle: String
        public let thing: Thing
    }

    public private(set) var entries: [Entry] = []
    private var exchangesMinted = 0
    private var memoriesMinted = 0

    public init(exchanges: [Exchange] = [], memories: [MemoryRecord] = []) {
        for exchange in exchanges {
            exchangesMinted += 1
            entries.append(Entry(handle: "p\(exchangesMinted)", thing: .exchange(exchange)))
        }
        _ = mint(memories)
    }

    /// Handles for records a step found; a record already in the table
    /// keeps its handle.
    @discardableResult
    public mutating func mint(_ records: [MemoryRecord]) -> [String] {
        records.map { record in
            if let existing = entries.first(where: { if case let .memory(known) = $0.thing { known.id == record.id } else { false } }) {
                return existing.handle
            }
            memoriesMinted += 1
            let handle = "m\(memoriesMinted)"
            entries.append(Entry(handle: handle, thing: .memory(record)))
            return handle
        }
    }

    public subscript(handle: String) -> Thing? {
        entries.first { $0.handle == handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }?.thing
    }

    public var handles: [String] { entries.map(\.handle) }
    public var exchangeEntries: [Entry] { entries.filter { if case .exchange = $0.thing { true } else { false } } }
    public var memoryEntries: [Entry] { entries.filter { if case .memory = $0.thing { true } else { false } } }

    /// One thing as the planner's listing gives it: its handle and what it is.
    public static func line(_ entry: Entry, now: Date, calendar: Calendar = .current) -> String {
        switch entry.thing {
        case let .exchange(exchange):
            return "\(entry.handle): \(exchange.described)"
        case let .memory(record):
            let label = record.kind.label
            let article = "aeiou".contains(label.first ?? "x") ? "An" : "A"
            var line = "\(entry.handle): \(article) \(label) from \(RecallRouting.when(record.date, now: now, calendar: calendar))"
            if let host = record.url?.host() { line += " (\(host))" }
            line += ": \"\(record.title)\""
            return line
        }
    }
}
