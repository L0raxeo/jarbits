import Foundation

/// What a recall query says about the thing wanted besides its words: its
/// kind ("the video", "that answer", "a picture") and when it was seen
/// ("yesterday", "this morning", "three days ago"). Read from the words
/// before the search strips them, and applied to what every memory record
/// already stores: its kind, its date and, for a page, its host.
public struct RecallFilters: Equatable, Sendable {
    /// Kinds the memory may be; nil when the query names none.
    public var kinds: Set<MemoryRecord.Kind>?
    /// The query asked for a video: a page on a video host, or titled as one.
    public var video: Bool
    /// When it was seen; nil when the query says nothing about it.
    public var window: DateInterval?
    /// The query asks for a set ("everything we talked about with the
    /// dyson", "all the videos from yesterday"), not one thing. Jev's
    /// reading when an intent came back, else the collection words.
    public var all: Bool
    /// The query names a particular thing to find. Jev's reading when an
    /// intent came back; nil in the fallback, where the shortlist decides
    /// from the words that are left.
    public var named: Bool?
    /// The query asks for the newest so many ("my last five searches", "the
    /// last 5 things I asked you", "my recent pictures"): that many, newest
    /// first, of the kinds named, with no judge asked. Nil when the query
    /// names no count.
    public var count: Int?

    public init(kinds: Set<MemoryRecord.Kind>? = nil, video: Bool = false, window: DateInterval? = nil, all: Bool = false, named: Bool? = nil, count: Int? = nil) {
        self.kinds = kinds
        self.video = video
        self.window = window
        self.all = all
        self.named = named
        self.count = count
    }

    /// Everything about a named thing: the kind words become no bar, every
    /// memory about it is wanted, and Jev is asked whether each is about it
    /// rather than whether it is the one. Needs a name (the judge's
    /// question is about the thing) and no count (a count says how many).
    /// `named` nil, the fallback, counts as named here; the shortlist then
    /// decides from the words.
    public var collection: Bool { all && named != false && count == nil }

    /// No kind, video or time constraint. A set or a count is not one: it
    /// says how many, not which.
    public var isEmpty: Bool { kinds == nil && !video && window == nil }

    static let collectionWords: Set<String> = ["everything", "all", "anything", "every"]

    /// "recent", "latest" and "last few" with no number mean this many.
    public static let defaultCount = 5
    /// The most a count may ask for; "my last hundred searches" is a scroll, not a recall.
    public static let maxCount = 20

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

    static let videoWords: Set<String> = ["video", "videos", "clip", "clips", "watching", "watched"]
    static let pageWords: Set<String> = ["article", "articles", "post", "page", "site", "website", "link", "reading", "read"]
    static let answerWords: Set<String> = ["answer", "answers", "chat", "chats", "convo", "conversation", "question", "questions", "asked", "told", "said", "talking", "talked", "ai"]
    static let pictureWords: Set<String> = ["picture", "pictures", "photo", "photos", "image", "images"]
    static let searchWords: Set<String> = ["search", "searched", "searches"]

    /// With `intent`, Jev's reading of the kinds, the name and the set
    /// replaces the word lists; the count and the time window are always
    /// read from the words, since a number and a day are not judgments.
    public static func parse(_ query: String, now: Date, calendar: Calendar = .current, intent: RecallIntent? = nil) -> RecallFilters {
        let words = MemorySearch.tokens(of: query)
        var filters = RecallFilters()
        filters.count = count(in: words)
        filters.window = window(in: words, now: now, calendar: calendar)
        if let intent {
            filters.kinds = intent.kinds
            filters.video = intent.video
            filters.named = intent.namesThing
            // A count says how many; "all that" after it is a figure of speech.
            filters.all = filters.count == nil && intent.wantsAll
            return filters
        }
        var kinds = Set<MemoryRecord.Kind>()
        if words.contains(where: videoWords.contains) {
            filters.video = true
            kinds.insert(.page)
        }
        if words.contains(where: pageWords.contains) { kinds.insert(.page) }
        if words.contains(where: answerWords.contains) { kinds.formUnion([.narrative, .oneLine]) }
        if words.contains(where: pictureWords.contains) { kinds.insert(.image) }
        if words.contains(where: searchWords.contains) { kinds.insert(.search) }
        if !kinds.isEmpty { filters.kinds = kinds }
        filters.all = filters.count == nil && words.contains(where: collectionWords.contains)
        return filters
    }

    public func allows(_ record: MemoryRecord) -> Bool {
        if let kinds, !kinds.contains(record.kind) { return false }
        if video, !record.isVideo { return false }
        if let window, !window.contains(record.date) { return false }
        return true
    }

    /// The day or span the words name, in the calendar's zone. Phrases are
    /// checked longest first: "earlier this week" is the week, not today.
    static func window(in words: [String], now: Date, calendar: Calendar) -> DateInterval? {
        let text = " " + words.joined(separator: " ") + " "
        func day(_ offset: Int) -> DateInterval? {
            guard let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        }
        func week(_ offset: Int) -> DateInterval? {
            guard let this = calendar.dateInterval(of: .weekOfYear, for: now),
                  let start = calendar.date(byAdding: .weekOfYear, value: offset, to: this.start),
                  let end = calendar.date(byAdding: .weekOfYear, value: offset, to: this.end) else { return nil }
            return DateInterval(start: start, end: end)
        }
        if text.contains(" this week ") { return week(0) }
        if text.contains(" last week ") { return week(-1) }
        if text.contains(" yesterday ") || text.contains(" last night ") { return day(-1) }
        if text.contains(" today ") || text.contains(" earlier ") || text.contains(" tonight ")
            || text.contains(" this morning ") || text.contains(" this afternoon ") || text.contains(" this evening ") {
            return day(0)
        }
        // "three days ago", "2 hours ago", "a week ago".
        if let ago = words.firstIndex(of: "ago"), ago >= 2, let count = number(words[ago - 2]) {
            let unit = words[ago - 1]
            if unit.hasPrefix("day") { return day(-count) }
            if unit.hasPrefix("week") { return week(-count) }
            if unit.hasPrefix("hour") { return DateInterval(start: now.addingTimeInterval(-Double(count) * 3600), end: now) }
        }
        return nil
    }

    /// "last five", "the last 5", "latest three", "5 most recent", "last
    /// few", "a couple of", or "recent" and "latest" alone for the default.
    /// "last week" and "last night" are time, read by `window`, not a count.
    static func count(in words: [String]) -> Int? {
        func clamp(_ n: Int) -> Int { min(max(n, 1), maxCount) }
        for (index, word) in words.enumerated() where word == "last" || word == "latest" || word == "past" {
            guard index + 1 < words.count else { continue }
            let next = words[index + 1]
            if let n = number(next), next != "a", next != "an" { return clamp(n) }
            if next == "few" { return 3 }
            if next == "couple" { return 2 }
        }
        if let index = words.firstIndex(of: "most"), index >= 1, index + 1 < words.count, words[index + 1] == "recent", let n = number(words[index - 1]) {
            return clamp(n)
        }
        if words.contains("couple") { return 2 }
        if words.contains("few") { return 3 }
        if words.contains("recent") || words.contains("latest") { return defaultCount }
        return nil
    }

    static func number(_ word: String) -> Int? {
        if let n = Int(word) { return n }
        if word == "a" || word == "an" { return 1 }
        let names = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return names.firstIndex(of: word).map { $0 + 1 }
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
