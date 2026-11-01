import Foundation

/// One open webpage: what a browser calls a tab, without a tab strip. A
/// page, or a results page (web or image results), that the user opened
/// and has not closed. It stays open across launches, reloading when the
/// user reaches it, and goes only when closed: by the user's word, or
/// when it stood ahead of the one the user was on as a new query opened.
/// Nothing expires. Answers, notes and the pages Jarbits reads on its own
/// screen are never webpages (2026-11-01, replacing memories).
public struct Webpage: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A page, by its address; brought forward as it is.
        case page
        /// A web results page, by what was searched.
        case search
        /// An image results page, by what was searched.
        case images

        /// The kind in words, for the grid.
        public var label: String {
            switch self {
            case .page: "page"
            case .search: "search"
            case .images: "picture search"
            }
        }

        /// The SF Symbol that stands for the kind, under a tile.
        public var symbol: String {
            switch self {
            case .page: "globe"
            case .search: "magnifyingglass"
            case .images: "photo"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    /// Where the webpage stands now: canonical for a page (no fragment, no
    /// tracking codes), the results address for a search.
    public var address: URL
    /// The page's title as it settled, else the words that opened it.
    public var title: String
    /// The words that opened it: the search term, the site asked for.
    /// Empty for a page browsed to from another.
    public var query: String
    /// When it was opened: the row's order, and "open since yesterday".
    public var opened: Date
    /// When the user last had it on screen.
    public var lastSeen: Date
    /// Where the page stood when it was last left: how far it was
    /// scrolled, and how far into its video; for a reload to the same spot.
    public var scrollY: Double?
    public var videoTime: Double?

    public init(id: UUID = UUID(), kind: Kind, address: URL, title: String? = nil, query: String = "", opened: Date = .now, lastSeen: Date? = nil, scrollY: Double? = nil, videoTime: Double? = nil) {
        self.id = id
        self.kind = kind
        self.address = kind == .page ? Self.canonical(address) : address
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (query.isEmpty ? (address.host() ?? address.absoluteString) : query)
        self.query = query
        self.opened = opened
        self.lastSeen = lastSeen ?? opened
        self.scrollY = scrollY
        self.videoTime = videoTime
    }

    /// The search term a results page shows, for a search; nil for a page.
    public var term: String? { kind == .page ? nil : (query.isEmpty ? nil : query) }

    /// What the meaning index keeps: the title, the query and the host,
    /// each on a line, nothing twice.
    public var indexText: String {
        var lines: [String] = []
        for line in [title, query, address.host()].compactMap({ $0 }) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !lines.contains(trimmed) { lines.append(trimmed) }
        }
        return lines.joined(separator: "\n")
    }

    /// Two webpages at the same thing: a page by address, a search by its
    /// kind and term.
    public func sameThing(as other: Webpage) -> Bool {
        guard kind == other.kind else { return false }
        if kind == .page { return address == other.address }
        return query.lowercased() == other.query.lowercased()
    }

    /// Query parameters that only track the click, never pick the page.
    static let trackingParameters: Set<String> = ["srsltid", "gclid", "fbclid", "msclkid", "ref", "ref_src"]

    /// The address without its fragment and without tracking codes
    /// (Google's `srsltid`, `utm_*`, click ids), so a page reached twice
    /// from results is one webpage.
    public static func canonical(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.fragment = nil
        if let items = parts.queryItems {
            let kept = items.filter { !trackingParameters.contains($0.name.lowercased()) && !$0.name.lowercased().hasPrefix("utm_") }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        return parts.url ?? url
    }

    /// Hosts whose pages are videos. Short and visible; grow it from the log.
    static let videoHosts = ["youtube.com", "youtu.be", "vimeo.com", "tiktok.com", "twitch.tv", "dailymotion.com", "netflix.com"]

    /// A page on a video host, or a page whose title says it is a video. A
    /// video host's front page (no path, as "go to youtube" opens it) is not
    /// one: it is the site, not something watched.
    public var isVideo: Bool {
        guard kind == .page else { return false }
        if let host = address.host()?.lowercased(),
           Self.videoHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
           address.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty == false {
            return true
        }
        return title.lowercased().contains("video")
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// How a recall fared, for the decision log: what was shortlisted, what
/// Jev picked, and which path answered.
public struct RecallSummary: Codable, Sendable, Equatable {
    /// How many webpages were shown: none, one (brought forward), or the grid's count.
    public var matches: Int
    /// The query asked for everything about something; absent on older rows.
    public var collection: Bool?
    /// The query asked for the newest so many; absent on older rows.
    public var count: Int?
    /// The kind of the webpage shown, when one was.
    public var picked: Webpage.Kind?
    /// How many candidates the filters and words shortlisted.
    public var shortlisted: Int?
    /// How many of them Jev said yes to, when Jev was asked.
    public var judged: Int?
    /// `jev`, `words` (no key, or nothing to judge), or the error Jev's request met.
    public var source: String?
    public var latencyMs: Int?

    public init(matches: Int, collection: Bool? = nil, count: Int? = nil, picked: Webpage.Kind? = nil, shortlisted: Int? = nil, judged: Int? = nil, source: String? = nil, latencyMs: Int? = nil) {
        self.matches = matches
        self.collection = collection
        self.count = count
        self.picked = picked
        self.shortlisted = shortlisted
        self.judged = judged
        self.source = source
        self.latencyMs = latencyMs
    }

    enum CodingKeys: String, CodingKey { case matches, collection, count, picked, shortlisted, judged, source, latencyMs }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matches = try c.decode(Int.self, forKey: .matches)
        collection = try c.decodeIfPresent(Bool.self, forKey: .collection)
        count = try c.decodeIfPresent(Int.self, forKey: .count)
        // Older rows name kinds that are no longer webpages (an answer, an action): read as none.
        picked = try? c.decodeIfPresent(Webpage.Kind.self, forKey: .picked)
        shortlisted = try c.decodeIfPresent(Int.self, forKey: .shortlisted)
        judged = try c.decodeIfPresent(Int.self, forKey: .judged)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        latencyMs = try c.decodeIfPresent(Int.self, forKey: .latencyMs)
    }
}

/// What a recall asks for besides its words: Jev's reading of the kinds,
/// the name and the set (`RecallIntent`), and the count and the span the
/// extractor read out of the words. Applied to what every open webpage
/// stores: its kind, when it was opened and, for a page, its host.
public struct RecallAsk: Equatable, Sendable {
    public var intent: RecallIntent?
    /// Kinds the webpage may be; nil when none is named, which means any.
    public var kinds: Set<Webpage.Kind>?
    /// The ask is for a video: a page on a video host, or titled as one.
    public var video: Bool
    /// The ask names a particular thing to find; nil without an intent,
    /// where the words that are left decide.
    public var named: Bool?
    /// The ask is for a set, not one thing; a count says how many instead.
    public var all: Bool
    /// "my last five searches": that many, newest first, no judge asked.
    public var count: Int?
    /// When it was opened, as the extractor read the words against today.
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
    /// webpage about it is wanted, and Jev is asked whether each is about it
    /// rather than whether it is the one. Needs a name and no count.
    public var collection: Bool { all && named != false && count == nil }

    /// No kind, video or time constraint. A set or a count is not one: it
    /// says how many, not which.
    public var isEmpty: Bool { kinds == nil && !video && window == nil }

    /// The kinds in words, for a grid's title: "videos and searches".
    public var kindsTitle: String {
        guard let kinds, !kinds.isEmpty else { return video ? "videos" : "webpages" }
        var names: [String] = []
        if video { names.append("videos") } else if kinds.contains(.page) { names.append("pages") }
        if kinds.contains(.images) { names.append("picture searches") }
        if kinds.contains(.search) { names.append("searches") }
        return names.joined(separator: " and ")
    }

    /// "Last 5 searches", for a count ask; nil otherwise.
    public var countTitle: String? {
        count.map { "Last \($0) \(kindsTitle)" }
    }

    /// "All videos", for a set of a kind with nothing named; nil otherwise.
    public var allTitle: String? {
        all && named == false && count == nil ? "All \(kindsTitle)" : nil
    }

    public func allows(_ webpage: Webpage) -> Bool {
        if let kinds, !kinds.contains(webpage.kind) { return false }
        if video, !webpage.isVideo { return false }
        if let window, !window.contains(webpage.opened) { return false }
        return true
    }
}

/// Word matching over the open webpages. The query's recall phrasing is
/// dropped ("that page about the dyson pencilvac" → "dyson", "pencilvac");
/// a webpage matches a term when one of its words contains it, or is a
/// near miss of it (one letter off, or the same long start: "hennessy"
/// against "hennessey", as dictation spells names), or, for long terms,
/// when its text with the spaces removed does ("pencilvac" against "pencil
/// vac"). Webpages holding every term win; failing that, those holding
/// any; newest opened first among equals. The text helpers (`terms`,
/// `tokens`, `close`, `interleave`) serve facts and notes too.
public enum WebpageSearch {

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

    /// The candidates for a recall: the webpages the ask allows (the kinds
    /// Jev read, the span and the count the extractor read), ranked by
    /// matches on the topic, then the rest of the allowed set newest first,
    /// so a judge still sees "the videos from yesterday" when no word
    /// matches a title. `ranked` is the meaning index's order, nearest
    /// first: when the request names a thing (terms, and no count), those of
    /// the allowed set take turns with the word matches, so "that car page"
    /// reaches a page whose title shares no word with it.
    public static func shortlist(_ webpages: [Webpage], topic: String?, ask: RecallAsk = RecallAsk(), limit: Int = limit, ranked: [UUID] = []) -> [Webpage] {
        let words = byWords(webpages, topic: topic, ask: ask, limit: limit)
        let terms = terms(of: topic)
        let named = ask.named ?? !terms.isEmpty
        guard !ranked.isEmpty, named, !terms.isEmpty, ask.count == nil else { return words }
        var filters = ask
        if filters.collection { filters.kinds = nil }
        let allowed = Set((filters.isEmpty ? webpages : webpages.filter(filters.allows)).map(\.id))
        let byID = Dictionary(webpages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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

    static func byWords(_ webpages: [Webpage], topic: String?, ask: RecallAsk, limit: Int) -> [Webpage] {
        var filters = ask
        let terms = terms(of: topic)
        let named = filters.named ?? !terms.isEmpty
        let hasTerms = named && !terms.isEmpty
        if filters.collection { filters.kinds = nil }
        let allowed = filters.isEmpty ? webpages : webpages.filter(filters.allows)
        func newest(_ n: Int) -> [Webpage] { Array(allowed.sorted { $0.opened > $1.opened }.prefix(n)) }
        // "my last five searches": the newest so many of the kinds named,
        // or of the word matches when the query names something too.
        if let count = filters.count {
            let pool = hasTerms ? matches(allowed, topic: topic, limit: allowed.count, preferFull: false) : allowed
            return Array(pool.sorted { $0.opened > $1.opened }.prefix(count))
        }
        guard hasTerms else {
            // Nothing named: the newest of what the filters allow. In the
            // fallback, with no filter either, there is nothing to go on.
            return filters.intent != nil || !filters.isEmpty ? newest(limit) : []
        }
        // A collection takes every webpage that holds any of the words, not
        // only those holding all: Jev then judges which are about the topic.
        var byWords = matches(allowed, topic: topic, limit: limit, preferFull: !filters.collection)
        if filters.collection { return byWords }
        if byWords.isEmpty, filters.kinds != nil {
            // The kind was wrong about the kind, so the rest of that kind is
            // noise, not a fallback.
            var relaxed = filters
            relaxed.kinds = nil
            byWords = matches(relaxed.isEmpty ? webpages : webpages.filter(relaxed.allows), topic: topic, limit: limit)
            if !byWords.isEmpty { return byWords }
        }
        guard !filters.isEmpty else { return byWords }
        let hit = Set(byWords.map(\.id))
        let rest = allowed.filter { !hit.contains($0.id) }.sorted { $0.opened > $1.opened }
        return Array((byWords + rest).prefix(limit))
    }

    public static func matches(_ webpages: [Webpage], topic: String?, limit: Int = limit, preferFull: Bool = true) -> [Webpage] {
        let terms = terms(of: topic)
        guard !terms.isEmpty else { return [] }
        let scored = webpages.compactMap { webpage -> (webpage: Webpage, hits: Int)? in
            let ordered = tokens(of: webpage.haystack)
            let words = Set(ordered)
            let joined = ordered.joined()
            let hits = terms.filter { term in
                words.contains { close(term, $0) } || (term.count >= joinedMinimum && joined.contains(term))
            }.count
            return hits > 0 ? (webpage, hits) : nil
        }
        let full = scored.filter { $0.hits == terms.count }
        let chosen = full.isEmpty || !preferFull ? scored : full
        return chosen
            .sorted { $0.hits != $1.hits ? $0.hits > $1.hits : $0.webpage.opened > $1.webpage.opened }
            .prefix(limit)
            .map(\.webpage)
    }

    /// Lowercased words; an apostrophe joins rather than splits, so
    /// "macy's" is one word, "macys", as a page's own words have it.
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

extension Webpage {
    /// Everything a term may match: the query, the title, the host and the path.
    var haystack: String {
        [query, title, address.host() ?? "", address.path()].joined(separator: " ")
    }
}
