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

    public init(kinds: Set<MemoryRecord.Kind>? = nil, video: Bool = false, window: DateInterval? = nil) {
        self.kinds = kinds
        self.video = video
        self.window = window
    }

    public var isEmpty: Bool { kinds == nil && !video && window == nil }

    static let videoWords: Set<String> = ["video", "videos", "clip", "clips", "watching", "watched"]
    static let pageWords: Set<String> = ["article", "articles", "post", "page", "site", "website", "link", "reading", "read"]
    static let answerWords: Set<String> = ["answer", "answers", "chat", "chats", "convo", "conversation", "question", "questions", "asked", "told", "said", "talking", "talked"]
    static let pictureWords: Set<String> = ["picture", "pictures", "photo", "photos", "image", "images"]
    static let searchWords: Set<String> = ["search", "searched"]

    public static func parse(_ query: String, now: Date, calendar: Calendar = .current) -> RecallFilters {
        let words = MemorySearch.tokens(of: query)
        var filters = RecallFilters()
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
        filters.window = window(in: words, now: now, calendar: calendar)
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
