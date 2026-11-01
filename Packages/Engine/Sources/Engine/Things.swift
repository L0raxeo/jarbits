import Foundation

/// A thing the planner can point at: an exchange of this session, an open
/// webpage, a note, or a link in view. The device knows each one exactly
/// (a page's address, a search's term, an answer's text); the planner only
/// ever names it by a handle from its listing, and the device swaps the
/// handle for the thing before a step runs. No model carries an address.
public enum Thing: Sendable, Equatable {
    case exchange(Exchange)
    case webpage(Webpage)
    case note(Note)
    /// A link in view on the page on screen.
    case item(ScreenItem)
}

/// What a thing is, exactly, for an instinct to act on.
public struct Reference: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case page, search, images, answer, recall, site, note
    }

    public var kind: Kind
    public var title: String
    public var address: URL?
    public var term: String?
    public var text: String?
    /// The open webpage this stands for, when it is one.
    public var webpageID: UUID?
    public var noteID: UUID?

    public init(kind: Kind, title: String, address: URL? = nil, term: String? = nil, text: String? = nil, webpageID: UUID? = nil, noteID: UUID? = nil) {
        self.kind = kind
        self.title = title
        self.address = address
        self.term = term
        self.text = text
        self.webpageID = webpageID
        self.noteID = noteID
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
            case .note:
                self.init(kind: .note, title: exchange.title ?? exchange.query, text: exchange.text, noteID: exchange.noteID)
            }
        case let .webpage(webpage):
            let kind: Kind = switch webpage.kind {
            case .page: .page
            case .search: .search
            case .images: .images
            }
            self.init(kind: kind, title: webpage.title, address: webpage.address, term: webpage.term, webpageID: webpage.id)
        case let .note(note):
            self.init(kind: .note, title: note.title, text: note.excerpt, noteID: note.id)
        case let .item(item):
            self.init(kind: .page, title: item.title, address: item.address)
        }
    }

    /// The thing as an exchange, for an answer's context block.
    public func asExchange(query: String) -> Exchange {
        switch kind {
        case .page:
            if let address { return .page(query: query, title: title, address: address) }
            return Exchange(query: query, kind: .page, title: title)
        case .search, .images: return .search(query: query, term: term ?? title)
        case .answer: return .answer(query: title, text: text ?? "")
        case .recall: return .recall(query: query, title: title, titles: [])
        case .site: return .site(query: query, name: title, hosts: [])
        case .note: return .note(query: query, title: title, excerpt: text ?? "", noteID: noteID)
        }
    }
}

extension Exchange {
    /// One exchange as a line of a model's context: what was done and got.
    public var described: String {
        // A page or search read on Jarbits's own screen says so: the user
        // never saw it, and the planner tells the two apart by this.
        let where_ = own == true ? " on my screen" : ""
        switch kind {
        case .answer: return "Asked \"\(query)\" and got: \(text ?? "")"
        case .page:
            if let title, let host { return "Read \"\(title)\" (\(host))" + where_ }
            else if let title { return "Read \"\(title)\"" + where_ }
            else { return "Read a page for \"\(query)\"" + where_ }
        case .search: return "Searched \"\(text ?? query)\"" + where_
        case .recall: return "Looked through earlier memories for \"\(query)\""
        case .site:
            if let text { return "Chose among sites for \"\(title ?? query)\": \(text)" }
            else { return "Chose among sites for \"\(title ?? query)\"" }
        case .note:
            // A write says what it did and what went in; an open, that it opened.
            if let text, text.hasPrefix("Added to ") || text.hasPrefix("Rewrote ") || text.hasPrefix("Made the note ") || text.hasPrefix("Took ") {
                let lines = wrote.map { $0.split(separator: "\n").map { "    " + String($0) }.joined(separator: "\n") }
                return "\(text) (my note \"\(title ?? query)\")" + (lines.map { ":\n" + $0 } ?? "")
            }
            return "Opened my note \"\(title ?? query)\""
        }
    }
}

/// The handles of one plan: `p1, p2…` for the exchanges the query depends
/// on (oldest first), `w1, w2…` for the open webpages (newest first),
/// `n1, n2…` for the notes, `s1, s2…` for the links in view on the screen,
/// and more webpages minted by a step's result. Nothing is renumbered, and
/// a table never outlives its plan.
public struct ThingTable: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let handle: String
        public let thing: Thing
    }

    public private(set) var entries: [Entry] = []
    private var exchangesMinted = 0
    private var webpagesMinted = 0
    private var notesMinted = 0
    private var itemsMinted = 0

    public init(exchanges: [Exchange] = [], webpages: [Webpage] = [], notes: [Note] = [], items: [ScreenItem] = []) {
        for exchange in exchanges { _ = mint(exchange: exchange) }
        _ = mint(webpages: webpages)
        _ = mint(notes: notes)
        _ = mint(items: items)
    }

    /// A handle for an exchange: the ones the plan began with, and a page
    /// a step opened on Jarbits's own screen, which the planner then names
    /// to look at, keep, or bring forward. An exchange already listed keeps
    /// its handle.
    @discardableResult
    public mutating func mint(exchange: Exchange) -> String {
        if let existing = entries.first(where: { if case let .exchange(known) = $0.thing { known == exchange } else { false } }) {
            return existing.handle
        }
        exchangesMinted += 1
        let handle = "p\(exchangesMinted)"
        entries.append(Entry(handle: handle, thing: .exchange(exchange)))
        return handle
    }

    /// Handles for the links in view, in their order on the screen.
    @discardableResult
    public mutating func mint(items: [ScreenItem]) -> [String] {
        items.map { item in
            itemsMinted += 1
            let handle = "s\(itemsMinted)"
            entries.append(Entry(handle: handle, thing: .item(item)))
            return handle
        }
    }

    /// Handles for notes the words may mean; a note already listed keeps its handle.
    @discardableResult
    public mutating func mint(notes: [Note]) -> [String] {
        notes.map { note in
            if let existing = entries.first(where: { if case let .note(known) = $0.thing { known.id == note.id } else { false } }) {
                return existing.handle
            }
            notesMinted += 1
            let handle = "n\(notesMinted)"
            entries.append(Entry(handle: handle, thing: .note(note)))
            return handle
        }
    }

    /// Handles for open webpages, the listing's and any a step found; a
    /// webpage already in the table keeps its handle.
    @discardableResult
    public mutating func mint(webpages: [Webpage]) -> [String] {
        webpages.map { webpage in
            if let existing = entries.first(where: { if case let .webpage(known) = $0.thing { known.id == webpage.id } else { false } }) {
                return existing.handle
            }
            webpagesMinted += 1
            let handle = "w\(webpagesMinted)"
            entries.append(Entry(handle: handle, thing: .webpage(webpage)))
            return handle
        }
    }

    public subscript(handle: String) -> Thing? {
        entries.first { $0.handle == handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }?.thing
    }

    public var handles: [String] { entries.map(\.handle) }
    public var exchangeEntries: [Entry] { entries.filter { if case .exchange = $0.thing { true } else { false } } }
    public var webpageEntries: [Entry] { entries.filter { if case .webpage = $0.thing { true } else { false } } }
    public var noteEntries: [Entry] { entries.filter { if case .note = $0.thing { true } else { false } } }
    public var itemEntries: [Entry] { entries.filter { if case .item = $0.thing { true } else { false } } }
    /// The items' handles, in screen order, for the screen block.
    public var itemHandles: [String] { itemEntries.map(\.handle) }
    /// Each notebook note's handle by its id, so an opened note's line can
    /// point at the notebook's entry.
    public var noteHandles: [UUID: String] {
        var out: [UUID: String] = [:]
        for entry in noteEntries { if case let .note(note) = entry.thing { out[note.id] = entry.handle } }
        return out
    }

    /// Each open webpage's handle by its canonical address, so a page
    /// exchange's line can point at the webpage it is.
    public var webpageHandles: [URL: String] {
        var out: [URL: String] = [:]
        for entry in webpageEntries { if case let .webpage(webpage) = entry.thing { out[webpage.address] = entry.handle } }
        return out
    }

    /// The handle of the thing on the screen, whatever kind it is: a note by
    /// its id (else its title), a page by its address (the open webpage it
    /// is, else the exchange), a search by its term, an answer by its query;
    /// nil for a grid or a card, which have no thing of their own. The
    /// listing names the screen by it, so "this" is one handle however the
    /// thing got into the listing.
    public func screenHandle(for screen: Screen, noteID: UUID? = nil) -> String? {
        func exchange(_ entry: Entry) -> Exchange? { if case let .exchange(x) = entry.thing { x } else { nil } }
        switch screen.kind {
        case .note:
            if let noteID, let handle = noteHandles[noteID] { return handle }
            return noteEntries.first { if case let .note(note) = $0.thing { note.title == screen.title } else { false } }?.handle
        case .page:
            guard let address = screen.address else { return nil }
            if let handle = webpageHandles[Webpage.canonical(address)] { return handle }
            if let open = webpageEntries.first(where: { if case let .webpage(w) = $0.thing { w.kind != .page && w.address == address } else { false } }) { return open.handle }
            if let page = exchangeEntries.last(where: { exchange($0).map { $0.kind == .page && $0.address == address.absoluteString && $0.own != true } ?? false }) { return page.handle }
            guard QueryParser.isSearchResults(address), let term = QueryParser.searchTerm(in: address)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            return exchangeEntries.last { exchange($0).map { $0.kind == .search && $0.text == term && $0.own != true } ?? false }?.handle
        case .answer:
            return exchangeEntries.last { exchange($0).map { $0.kind == .answer && $0.query == screen.title } ?? false }?.handle
        case .grid, .other:
            return nil
        }
    }

    /// One thing as the planner's listing gives it: its handle and what it
    /// is; an opened note names the notebook's handle for the same note
    /// when `noteHandles` has it, and a page the user saw names the open
    /// webpage it is when `webpageHandles` has it.
    public static func line(_ entry: Entry, now: Date, calendar: Calendar = .current, noteHandles: [UUID: String] = [:], webpageHandles: [URL: String] = [:], withWords: Bool = false) -> String {
        switch entry.thing {
        case let .exchange(exchange):
            // The user's own words first, when the listing carries them and
            // they are not the line's query already.
            var lead = "\(entry.handle): "
            if withWords, let asked = exchange.asked?.trimmingCharacters(in: .whitespacesAndNewlines), !asked.isEmpty, asked.lowercased() != exchange.query.lowercased() {
                lead += "You asked \"\(asked)\" → "
            }
            if exchange.kind == .note, let id = exchange.noteID, let handle = noteHandles[id] {
                return "\(lead)\(exchange.described) (\(handle))"
            }
            if exchange.kind == .page, exchange.own != true, let address = exchange.address.flatMap(URL.init(string:)), let handle = webpageHandles[Webpage.canonical(address)] {
                return "\(lead)\(exchange.described) (\(handle))"
            }
            return "\(lead)\(exchange.described)"
        case let .webpage(webpage):
            let since = RecallRouting.when(webpage.opened, now: now, calendar: calendar)
            switch webpage.kind {
            case .page:
                var line = "\(entry.handle): A page open since \(since)"
                if let host = webpage.address.host() { line += " (\(host))" }
                return line + ": \"\(webpage.title)\""
            case .search: return "\(entry.handle): A search for \"\(webpage.query)\", open since \(since)"
            case .images: return "\(entry.handle): A picture search for \"\(webpage.query)\", open since \(since)"
            }
        case let .note(note):
            // The note whole, its lines numbered, under its heading line: the
            // planner writes into it by line, so it sees every line.
            let heading = "\(entry.handle): My note \"\(note.title)\", edited \(RecallRouting.when(note.edited, now: now, calendar: calendar))"
            let lines = note.numberedLines
            guard !lines.isEmpty else { return heading + " (empty)" }
            return ([heading + ":"] + lines.map { "    " + $0 }).joined(separator: "\n")
        case let .item(item):
            return "\(entry.handle): \(item.described)"
        }
    }
}
