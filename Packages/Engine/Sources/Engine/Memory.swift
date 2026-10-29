import Foundation

/// One thing the user saw, or several that belong together: a page, a
/// results page, an answer and its follow-ups, a picture; later a note or a
/// reminder attached to one of those. Written to the memories file on the
/// device as the result appears, and found again by `MemorySearch` when a
/// query is routed to `recall`.
///
/// A memory is an ordered list of `parts`. The first is the head: it
/// decides the kind, the tile, the title's default, what a tap opens and
/// what counts as the same thing. `cameFrom` is the memory that was on
/// screen when this one was made (the search before a page, the page
/// before the next), by id only. `kept` marks a long-term memory; the rest
/// are short-term and go a week after they were last touched (`date`).
public struct MemoryRecord: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A page that loaded, with its address; replays by loading it.
        case page
        /// A narrative answer, with its text; replays from the text.
        case narrative
        /// A one-line answer. Alone, replays by asking the query again;
        /// grown into a conversation (`turns`), from its turns.
        case oneLine = "one_line"
        /// A picture; replays by asking the query again.
        case image
        /// A results page; replays by asking the query again.
        case search
        /// Something a plan did with no screen of its own (a fact kept, a
        /// call made), by its name and what came of it; replays from the text.
        case action

        /// The kind in words, for the picker.
        public var label: String {
            switch self {
            case .page: "page"
            case .narrative: "answer"
            case .oneLine: "answer"
            case .image: "picture"
            case .search: "search"
            case .action: "action"
            }
        }

        /// The SF Symbol that stands for the kind, under a tile.
        public var symbol: String {
            switch self {
            case .page: "globe"
            case .narrative, .oneLine: "text.alignleft"
            case .image: "photo"
            case .search: "magnifyingglass"
            case .action: "bolt"
            }
        }
    }

    /// The shape written today; lines without a version are the flat shape
    /// from before parts, read by `init(from:)` and rewritten in this one.
    public static let currentVersion = 2
    /// A short-term memory goes this long after it was last touched.
    public static let shortTermWindow: TimeInterval = 7 * 86_400

    public var id: UUID
    /// When last seen; a repeat within a day refreshes it.
    public var date: Date
    /// The head's own title (a page's title), else the query.
    public var title: String
    /// The words that started this memory: the search, the question. Empty
    /// for a page browsed on from a search.
    public var query: String
    /// Head first; never empty.
    public var parts: [MemoryPart]
    /// The memory on screen when this one was made; nil at the start of a
    /// run. A dangling id (the older memory flushed) just ends the chain.
    public var cameFrom: UUID?
    /// Long-term: when it was promoted. Nil is short-term.
    public var kept: Date?
    public var version: Int

    public init(id: UUID = UUID(), date: Date = .now, title: String? = nil, query: String = "", parts: [MemoryPart], cameFrom: UUID? = nil, kept: Date? = nil) {
        precondition(!parts.isEmpty, "a memory has at least its head")
        self.id = id
        self.date = date
        self.query = query
        self.parts = parts
        self.title = title ?? parts[0].content.ownTitle ?? query
        self.cameFrom = cameFrom
        self.kept = kept
        self.version = Self.currentVersion
    }

    /// The flat shape, as a factory: one part per kind, a conversation as
    /// one answer part per turn. What the session and the tests build with.
    /// The parts' ids derive from the record's, so two builds of the same
    /// flat record are equal.
    public init(id: UUID = UUID(), date: Date = .now, kind: Kind, query: String, title: String? = nil, url: URL? = nil, text: String? = nil, turns: [AnswerTurn]? = nil, cameFrom: UUID? = nil, kept: Date? = nil) {
        let parts = Self.parts(for: id, kind: kind, query: query, title: title, url: url, text: text, turns: turns)
        self.init(id: id, date: date, title: title ?? query, query: query, parts: parts, cameFrom: cameFrom, kept: kept)
    }

    /// Stands in for a page's address when the flat shape had none (a
    /// fixture); `url` reads it back as nil.
    static let noAddress = URL(string: "about:blank")!

    static func parts(for id: UUID, kind: Kind, query: String, title: String?, url: URL?, text: String?, turns: [AnswerTurn]?) -> [MemoryPart] {
        let contents: [MemoryPart.Content]
        switch kind {
        case .page:
            contents = [.page(address: url ?? noAddress, title: title ?? query)]
        case .search:
            contents = [.search(query: query)]
        case .image:
            contents = [.picture(query: query)]
        case .narrative, .oneLine:
            if let turns, !turns.isEmpty {
                contents = turns.map { .answer(question: $0.query, text: $0.answer, format: $0.format) }
            } else {
                contents = [.answer(question: query, text: text ?? "", format: kind == .oneLine ? .oneLine : .narrative)]
            }
        case .action:
            contents = [.action(name: title ?? "action", arguments: .object([:]), result: text ?? "")]
        }
        return contents.enumerated().map { index, content in MemoryPart(id: MemoryPart.derivedID(from: id, index: index), content) }
    }

    // MARK: Read through the head

    public var head: MemoryPart { parts[0] }

    public var kind: Kind {
        switch head.content {
        case .page: .page
        case .search: .search
        case .picture: .image
        case let .answer(_, _, format): format == .oneLine ? .oneLine : .narrative
        case .note: .narrative
        case .action: .action
        }
    }

    /// The head page's address.
    public var url: URL? {
        if case let .page(address, _) = head.content, address != Self.noAddress { return address }
        return nil
    }

    /// The first answer's markup, as `AnswerMarkup` renders it, or what an
    /// action came to; nil when there is none or it is empty (a bare
    /// one-line answer).
    public var text: String? {
        switch head.content {
        case let .answer(_, text, _): text.isEmpty ? nil : text
        case let .action(_, _, result): result.isEmpty ? nil : result
        default: nil
        }
    }

    /// What the meaning index keeps for the memory: the title, the query,
    /// the page's host, and the first words of an answer's text, each on a
    /// line, nothing twice.
    public var indexText: String {
        var lines: [String] = []
        for line in [title, query, url?.host(), text.map { String($0.prefix(300)) }].compactMap({ $0 }) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !lines.contains(trimmed) { lines.append(trimmed) }
        }
        return lines.joined(separator: "\n")
    }

    /// Every answer part as a turn, first to last.
    public var exchanges: [AnswerTurn] {
        parts.compactMap { part in
            if case let .answer(question, text, format) = part.content { return AnswerTurn(query: question, answer: text, format: format) }
            return nil
        }
    }

    /// A conversation's turns, when there are at least two; nil for a
    /// single answer, as the flat shape had it.
    public var turns: [AnswerTurn]? {
        let all = exchanges
        return all.count > 1 ? all : nil
    }

    /// Two records of the same thing: a page by address, anything else by
    /// kind and query. A repeat within a day refreshes the date.
    public func sameThing(as other: MemoryRecord) -> Bool {
        guard kind == other.kind else { return false }
        if kind == .page { return url == other.url }
        return query.lowercased() == other.query.lowercased()
    }

    /// Short-term and untouched for longer than the window.
    public func expires(by now: Date) -> Bool {
        kept == nil && now.timeIntervalSince(date) > Self.shortTermWindow
    }

    /// Query parameters that only track the click, never pick the page.
    static let trackingParameters: Set<String> = ["srsltid", "gclid", "fbclid", "msclkid", "ref", "ref_src"]

    /// The address without its fragment and without tracking codes
    /// (Google's `srsltid`, `utm_*`, click ids), so a page reached twice
    /// from results is one memory.
    public static func canonical(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.fragment = nil
        if let items = parts.queryItems {
            let kept = items.filter { !trackingParameters.contains($0.name.lowercased()) && !$0.name.lowercased().hasPrefix("utm_") }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        return parts.url ?? url
    }

    // MARK: Both shapes on disk

    enum CodingKeys: String, CodingKey {
        case id, date, title, query, parts, cameFrom, kept, version
        // The flat shape, read only.
        case kind, url, text, turns
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
        cameFrom = try c.decodeIfPresent(UUID.self, forKey: .cameFrom)
        kept = try c.decodeIfPresent(Date.self, forKey: .kept)
        version = Self.currentVersion
        if c.contains(.parts) {
            // A part this build cannot read is dropped; a record left with
            // nothing is not a memory.
            let read = try c.decode([Tolerant<MemoryPart>].self, forKey: .parts).compactMap(\.value)
            guard !read.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .parts, in: c, debugDescription: "no readable part")
            }
            parts = read
        } else {
            let kind = try c.decode(Kind.self, forKey: .kind)
            parts = Self.parts(
                for: id, kind: kind, query: query,
                title: try c.decodeIfPresent(String.self, forKey: .title),
                url: try c.decodeIfPresent(URL.self, forKey: .url),
                text: try c.decodeIfPresent(String.self, forKey: .text),
                turns: try c.decodeIfPresent([AnswerTurn].self, forKey: .turns)
            )
        }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? parts[0].content.ownTitle ?? query
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(title, forKey: .title)
        try c.encode(query, forKey: .query)
        try c.encode(parts, forKey: .parts)
        try c.encodeIfPresent(cameFrom, forKey: .cameFrom)
        try c.encodeIfPresent(kept, forKey: .kept)
        try c.encode(version, forKey: .version)
    }
}

/// One piece of a memory. Each case is one format with its own fields, so
/// every reader handles every kind by compiler's order, and a new kind
/// later is a new case.
public struct MemoryPart: Codable, Sendable, Hashable, Identifiable {
    public enum Content: Codable, Sendable, Hashable {
        /// A page, by address and title.
        case page(address: URL, title: String)
        /// A results page, by what was searched.
        case search(query: String)
        /// One exchange: a question and its answer, narrative or one-line.
        case answer(question: String, text: String, format: Instinct)
        /// A picture result, by what was asked for.
        case picture(query: String)
        /// Words the user attached. Not produced yet.
        case note(text: String)
        /// Something a plan did with no screen of its own: the tool by name,
        /// what it was given, and what came of it.
        case action(name: String, arguments: JSONValue, result: String)

        /// The title a part brings of its own: a page's, or what an action
        /// came to. The rest take the memory's query.
        var ownTitle: String? {
            switch self {
            case let .page(_, title): title
            case let .action(name, _, result): result.isEmpty ? name : result
            default: nil
            }
        }
    }

    public var id: UUID
    public var content: Content

    public init(id: UUID = UUID(), _ content: Content) {
        self.id = id
        self.content = content
    }

    /// A part id that follows from its record's id and its position, for
    /// parts built from the flat shape: the record's bytes with the index
    /// folded into the last two.
    static func derivedID(from record: UUID, index: Int) -> UUID {
        var bytes = record.uuid
        bytes.14 ^= UInt8(truncatingIfNeeded: index >> 8)
        bytes.15 ^= UInt8(truncatingIfNeeded: index)
        return UUID(uuid: bytes)
    }
}

/// Decodes to nil instead of failing, so one unreadable element does not
/// take a whole list with it.
struct Tolerant<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) {
        value = try? T(from: decoder)
    }
}

/// How a recall fared, for the decision log: what was shortlisted, what
/// Jev picked, and which path answered.
public struct RecallSummary: Codable, Sendable, Equatable {
    /// How many memories were shown: none (web), one (opened), or the picker's count.
    public var matches: Int
    /// The query asked for everything about something; absent on older rows.
    public var collection: Bool?
    /// The query asked for the newest so many; absent on older rows.
    public var count: Int?
    /// The kind of the memory shown, when one was.
    public var picked: MemoryRecord.Kind?
    /// How many candidates the filters and words shortlisted.
    public var shortlisted: Int?
    /// How many of them Jev said yes to, when Jev was asked.
    public var judged: Int?
    /// `jev`, `words` (no key, or nothing to judge), or the error Jev's request met.
    public var source: String?
    public var latencyMs: Int?

    public init(matches: Int, collection: Bool? = nil, count: Int? = nil, picked: MemoryRecord.Kind? = nil, shortlisted: Int? = nil, judged: Int? = nil, source: String? = nil, latencyMs: Int? = nil) {
        self.matches = matches
        self.collection = collection
        self.count = count
        self.picked = picked
        self.shortlisted = shortlisted
        self.judged = judged
        self.source = source
        self.latencyMs = latencyMs
    }
}

/// What a recall asks for besides its words: Jev's reading of the kinds,
/// the name and the set (`RecallIntent`), and the count and the span the
/// extractor read out of the words. Applied to what every memory record
/// already stores: its kind, its date and, for a page, its host.
public struct RecallAsk: Equatable, Sendable {
    public var intent: RecallIntent?
    /// Kinds the memory may be; nil when none is named, which means any.
    public var kinds: Set<MemoryRecord.Kind>?
    /// The ask is for a video: a page on a video host, or titled as one.
    public var video: Bool
    /// The ask names a particular thing to find; nil without an intent,
    /// where the words that are left decide.
    public var named: Bool?
    /// The ask is for a set, not one thing; a count says how many instead.
    public var all: Bool
    /// "my last five searches": that many, newest first, no judge asked.
    public var count: Int?
    /// When it was seen, as the extractor read the words against today.
    public var window: DateInterval?

    /// The most a count may ask for; "my last hundred searches" is a scroll, not a recall.
    public static let maxCount = 20

    public init(intent: RecallIntent? = nil, count: Int? = nil, window: DateInterval? = nil) {
        self.intent = intent
        kinds = intent?.kinds
        video = intent?.video ?? false
        named = intent?.namesThing
        self.count = count.map { min(max($0, 1), Self.maxCount) }
        all = count == nil && (intent?.wantsAll ?? false)
        self.window = window
    }

    /// Everything about a named thing: the kinds become no bar, every
    /// memory about it is wanted, and Jev is asked whether each is about it
    /// rather than whether it is the one. Needs a name and no count.
    public var collection: Bool { all && named != false && count == nil }

    /// No kind, video or time constraint. A set or a count is not one: it
    /// says how many, not which.
    public var isEmpty: Bool { kinds == nil && !video && window == nil }

    /// The kinds in words, for a picker's title: "searches and answers".
    public var kindsTitle: String {
        guard let kinds, !kinds.isEmpty else { return video ? "videos" : "memories" }
        var names: [String] = []
        if video { names.append("videos") } else if kinds.contains(.page) { names.append("pages") }
        if kinds.contains(.narrative) || kinds.contains(.oneLine) { names.append("answers") }
        if kinds.contains(.image) { names.append("pictures") }
        if kinds.contains(.search) { names.append("searches") }
        return names.joined(separator: " and ")
    }

    /// "Last 5 searches and answers", for a count ask; nil otherwise.
    public var countTitle: String? {
        count.map { "Last \($0) \(kindsTitle)" }
    }

    /// "All videos", for a set of a kind with nothing named; nil otherwise.
    public var allTitle: String? {
        all && named == false && count == nil ? "All \(kindsTitle)" : nil
    }

    public func allows(_ record: MemoryRecord) -> Bool {
        if let kinds, !kinds.contains(record.kind) { return false }
        if video, !record.isVideo { return false }
        if let window, !window.contains(record.date) { return false }
        return true
    }
}

extension MemoryRecord {
    /// Hosts whose pages are videos. Short and visible; grow it from the log.
    static let videoHosts = ["youtube.com", "youtu.be", "vimeo.com", "tiktok.com", "twitch.tv", "dailymotion.com", "netflix.com"]

    /// A page on a video host, or a page whose title says it is a video. A
    /// video host's front page (no path, as "go to youtube" opens it) is not
    /// one: it is the site, not something watched, and it would otherwise
    /// be the newest "video" every time.
    public var isVideo: Bool {
        guard kind == .page else { return false }
        if let url, let host = url.host()?.lowercased(),
           Self.videoHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
           url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty == false {
            return true
        }
        return title.lowercased().contains("video")
    }
}

/// Word matching over the memories. The query's recall phrasing is dropped
/// ("remember that convo on the dyson pencilvac" → "dyson", "pencilvac");
/// a record matches a term when one of its words contains it, or is a near
/// miss of it (one letter off, or the same long start: "hennessy" against
/// "hennessey", as dictation spells names), or, for long terms, when its
/// text with the spaces removed does ("pencilvac" against "pencil vac").
/// Records holding every term win; failing that, records holding any;
/// newest first among equals.
public enum MemorySearch {

    /// At least this long before a term may match inside joined-up text.
    static let joinedMinimum = 6

    /// The most matches a recall returns.
    public static let limit = 10

    /// The words of a topic, the thing to bring back as the extractor read
    /// it out of the request ("that thing about gingivitis again" →
    /// "gingivitis"); nothing here decides which words count.
    public static func terms(of topic: String?) -> [String] {
        var seen = Set<String>()
        return tokens(of: topic ?? "").filter { $0.count >= 2 && seen.insert($0).inserted }
    }

    /// The candidates for a recall: the records the ask allows (the kinds
    /// Jev read, the span and the count the extractor read), ranked by
    /// matches on the topic (the thing to bring back, the extractor's value),
    /// then the rest of the allowed set newest first, so a judge still sees
    /// "the videos from yesterday" when no word matches a title.
    ///
    /// Jev's intent decides the kinds, whether a thing is named and whether
    /// a set is wanted; the topic supplies the terms. Nothing named means
    /// no word matching at all, so "the last 5 things we were looking at"
    /// is immune to any word in it: the newest of the allowed set, as many
    /// as the count or the limit. Without an intent (no key, an error) the
    /// topic alone decides: the kind is no bar, and with no span, no count
    /// and no topic there is nothing to go on.
    ///
    /// `ranked` is the meaning index's order: the ids of the records nearest
    /// the topic in meaning, nearest first. When the request names a thing
    /// (terms, and no count), those of the allowed set come first, taking
    /// turns with the word matches, so "that car page" reaches a page whose
    /// title shares no word with it. A count or nothing named is by recency,
    /// as before, whatever the index says.
    public static func shortlist(_ records: [MemoryRecord], topic: String?, ask: RecallAsk = RecallAsk(), limit: Int = limit, ranked: [UUID] = []) -> [MemoryRecord] {
        let words = byWords(records, topic: topic, ask: ask, limit: limit)
        let terms = terms(of: topic)
        let named = ask.named ?? !terms.isEmpty
        guard !ranked.isEmpty, named, !terms.isEmpty, ask.count == nil else { return words }
        var filters = ask
        if filters.collection { filters.kinds = nil }
        let allowed = Set((filters.isEmpty ? records : records.filter(filters.allows)).map(\.id))
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let near = ranked.filter { allowed.contains($0) }.compactMap { byID[$0] }
        return interleave(near, words, limit: limit)
    }

    /// Two orders made one: the first of each in turn, nothing twice, at
    /// most `limit`.
    public static func interleave<T: Identifiable>(_ first: [T], _ second: [T], limit: Int) -> [T] {
        var seen = Set<T.ID>()
        var out: [T] = []
        var i = 0, j = 0
        while out.count < limit, i < first.count || j < second.count {
            if i < first.count {
                if seen.insert(first[i].id).inserted { out.append(first[i]) }
                i += 1
            }
            if out.count < limit, j < second.count {
                if seen.insert(second[j].id).inserted { out.append(second[j]) }
                j += 1
            }
        }
        return out
    }

    static func byWords(_ records: [MemoryRecord], topic: String?, ask: RecallAsk, limit: Int) -> [MemoryRecord] {
        var filters = ask
        let terms = terms(of: topic)
        let named = filters.named ?? !terms.isEmpty
        let hasTerms = named && !terms.isEmpty
        if filters.collection { filters.kinds = nil }
        let allowed = filters.isEmpty ? records : records.filter(filters.allows)
        func newest(_ n: Int) -> [MemoryRecord] { Array(allowed.sorted { $0.date > $1.date }.prefix(n)) }
        // "my last five searches": the newest so many of the kinds named,
        // or of the word matches when the query names something too. The
        // ask is for a count, not a thing, so no judge is needed.
        if let count = filters.count {
            let pool = hasTerms ? matches(allowed, topic: topic, limit: allowed.count, preferFull: false) : allowed
            return Array(pool.sorted { $0.date > $1.date }.prefix(count))
        }
        guard hasTerms else {
            // Nothing named: the newest of what the filters allow. In the
            // fallback, with no filter either, there is nothing to go on.
            return filters.intent != nil || !filters.isEmpty ? newest(limit) : []
        }
        // A collection takes every record that holds any of the words, not
        // only those holding all: Jev then judges which are about the topic.
        var byWords = matches(allowed, topic: topic, limit: limit, preferFull: !filters.collection)
        if filters.collection { return byWords }
        if byWords.isEmpty, filters.kinds != nil {
            // The kind was wrong about the kind, so the rest of that kind is
            // noise, not a fallback; and with no match at all the topic goes
            // to the web as before.
            var relaxed = filters
            relaxed.kinds = nil
            byWords = matches(relaxed.isEmpty ? records : records.filter(relaxed.allows), topic: topic, limit: limit)
            if !byWords.isEmpty { return byWords }
        }
        guard !filters.isEmpty else { return byWords }
        let hit = Set(byWords.map(\.id))
        let rest = allowed.filter { !hit.contains($0.id) }.sorted { $0.date > $1.date }
        return Array((byWords + rest).prefix(limit))
    }

    public static func matches(_ records: [MemoryRecord], topic: String?, limit: Int = limit, preferFull: Bool = true) -> [MemoryRecord] {
        let terms = terms(of: topic)
        guard !terms.isEmpty else { return [] }
        let scored = records.compactMap { record -> (record: MemoryRecord, hits: Int)? in
            let ordered = tokens(of: record.haystack)
            let words = Set(ordered)
            let joined = ordered.joined()
            let hits = terms.filter { term in
                words.contains { close(term, $0) } || (term.count >= joinedMinimum && joined.contains(term))
            }.count
            return hits > 0 ? (record, hits) : nil
        }
        let full = scored.filter { $0.hits == terms.count }
        let chosen = full.isEmpty || !preferFull ? scored : full
        return chosen
            .sorted { $0.hits != $1.hits ? $0.hits > $1.hits : $0.record.date > $1.record.date }
            .prefix(limit)
            .map(\.record)
    }

    /// Lowercased words; an apostrophe joins rather than splits, so
    /// "macy's" is one word, "macys", as a memory's own words have it.
    static func tokens(of text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "\u{2019}" }
            .map { String($0.filter { $0 != "'" && $0 != "\u{2019}" }) }
            .filter { !$0.isEmpty }
    }

    /// Near-matching is for names, so it needs a few letters to go on.
    static let nearMinimum = 5

    /// `word` contains `term`; or both are long enough and share all but
    /// the last letter or two of the shorter; or they are one edit apart.
    static func close(_ term: String, _ word: String) -> Bool {
        if word.contains(term) { return true }
        guard term.count >= nearMinimum, word.count >= nearMinimum else { return false }
        let shared = zip(term, word).prefix { $0 == $1 }.count
        if shared >= nearMinimum && shared >= min(term.count, word.count) - 1 { return true }
        return abs(term.count - word.count) <= 1 && editDistance(term, word) <= 1
    }

    /// Levenshtein distance, for two short words.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

extension MemoryRecord {
    /// Everything a term may match: the query, the title, and each part's
    /// words: a page's host and path, a search, every question and answer,
    /// a note.
    var haystack: String {
        var words = [query, title]
        for part in parts {
            switch part.content {
            case let .page(address, title):
                if let host = address.host() { words.append(host) }
                words.append(address.path())
                words.append(title)
            case let .search(query):
                words.append(query)
            case let .answer(question, text, _):
                words.append(question)
                words.append(text)
            case let .picture(query):
                words.append(query)
            case let .note(text):
                words.append(text)
            case let .action(name, _, result):
                words.append(name)
                words.append(result)
            }
        }
        return words.joined(separator: " ")
    }
}
