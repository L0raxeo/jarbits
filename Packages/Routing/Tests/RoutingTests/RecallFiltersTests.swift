import Foundation
import Testing
@testable import Routing

@Suite struct RecallFiltersTests {
    /// Thursday 22 October 2026, 11:13 in Chicago.
    private let now = Date(timeIntervalSince1970: 1_792_685_600)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func parse(_ query: String) -> RecallFilters {
        RecallFilters.parse(query, now: now, calendar: calendar)
    }

    private func day(_ offset: Int) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    @Test func everythingAsksForACollection() {
        let everything = parse("Pull up everything we talked about with the Dyson PencilVac")
        #expect(everything.collection)
        #expect(everything.kinds == [.narrative, .oneLine], "the kind words are still read; the shortlist decides what to do with them")
        #expect(parse("all the videos I watched yesterday").collection)
        #expect(parse("anything about lisbon").collection)
        #expect(!parse("that answer about hot chocolate").collection)
        #expect(!parse("the video from yesterday").collection)
        #expect(RecallFilters(all: true).isEmpty, "a set ask alone is no constraint")
    }

    @Test func aCountAsksForTheNewestSoMany() {
        #expect(parse("Pull up my last five queries").count == 5)
        #expect(parse("Pull up my last 5 queries").count == 5)
        let spoken = parse("You'll pull up the last 5 things I asked you, like including Google searches and AI stuff, and all that")
        #expect(spoken.count == 5)
        #expect(spoken.kinds == [.narrative, .oneLine, .search])
        #expect(spoken.countTitle == "Last 5 answers and searches")
        #expect(parse("my latest three pictures").count == 3)
        #expect(parse("the 3 most recent videos I watched").count == 3)
        #expect(parse("the last few pages").count == 3)
        #expect(parse("a couple of recent answers").count == 2)
        #expect(parse("my recent searches").count == RecallFilters.defaultCount)
        #expect(parse("my last 50 searches").count == RecallFilters.maxCount)
        #expect(parse("my last hundred searches").count == nil, "not a number the filters know")
        #expect(parse("the video from last week").count == nil, "last week is a time")
        #expect(parse("last night's video").count == nil)
        #expect(parse("that answer about hot chocolate").count == nil)
        #expect(parse("my last five searches").countTitle == "Last 5 searches")
        #expect(parse("the last 4 things").countTitle == "Last 4 memories")
        #expect(parse("last 2 videos").countTitle == "Last 2 videos")
    }

    @Test func kindWordsNameWhatIsWanted() {
        let videos = parse("Can you pull up the videos I was watching yesterday")
        #expect(videos.video)
        #expect(videos.kinds == [.page])
        #expect(parse("that answer about hot chocolate").kinds == [.narrative, .oneLine])
        #expect(parse("the pictures I looked at").kinds == [.image])
        let article = parse("that article on reddit")
        #expect(article.kinds == [.page])
        #expect(!article.video)
        #expect(parse("what did I search for").kinds == [.search])
        #expect(parse("remember the dyson pencilvac").isEmpty)
        #expect(!parse("that watch I was looking at").video, "a wristwatch is not a video")
    }

    @Test func timeWordsNameWhen() {
        #expect(parse("videos from yesterday").window == day(-1))
        #expect(parse("the thing from last night").window == day(-1))
        #expect(parse("what I read this morning").window == day(0))
        #expect(parse("that page from earlier").window == day(0))
        #expect(parse("the site from three days ago").window == day(-3))
        #expect(parse("the site from 2 days ago").window == day(-2))
        let hours = parse("the page from two hours ago").window
        #expect(hours?.end == now)
        #expect(hours?.start == now.addingTimeInterval(-7_200))
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)!
        #expect(parse("earlier this week").window == thisWeek, "the week, not today")
        #expect(parse("last week").window?.end == thisWeek.start)
        #expect(parse("remember the dyson pencilvac").window == nil)
    }

    @Test func filtersAllowByKindDateAndHost() {
        let yesterday = now.addingTimeInterval(-86_400)
        let video = MemoryRecord(date: yesterday, kind: .page, query: "", title: "Rick Steves' Europe: Lisbon", url: URL(string: "https://m.youtube.com/watch?v=a"))
        let article = MemoryRecord(date: yesterday, kind: .page, query: "", title: "Lisbon travel guide", url: URL(string: "https://www.ricksteves.com/lisbon"))
        let oldVideo = MemoryRecord(date: now.addingTimeInterval(-5 * 86_400), kind: .page, query: "", title: "Porto", url: URL(string: "https://youtu.be/b"))
        let answer = MemoryRecord(date: yesterday, kind: .narrative, query: "how do you make hot chocolate", text: "Heat milk.")
        let filters = parse("the videos I was watching yesterday")
        #expect(filters.allows(video))
        #expect(!filters.allows(article), "not a video")
        #expect(!filters.allows(oldVideo), "not yesterday")
        #expect(!filters.allows(answer), "not a page")
        #expect(parse("that answer from yesterday").allows(answer))
        #expect(RecallFilters().allows(answer), "no filter allows everything")
    }

    @Test func aVideoIsKnownByItsHostOrTitle() {
        #expect(MemoryRecord(kind: .page, query: "", title: "x", url: URL(string: "https://m.youtube.com/watch?v=a")).isVideo)
        #expect(MemoryRecord(kind: .page, query: "", title: "x", url: URL(string: "https://youtu.be/a")).isVideo)
        #expect(MemoryRecord(kind: .page, query: "", title: "x", url: URL(string: "https://www.tiktok.com/@a/video/1")).isVideo)
        #expect(!MemoryRecord(kind: .page, query: "", title: "Lisbon guide", url: URL(string: "https://www.ricksteves.com/")).isVideo)
        #expect(MemoryRecord(kind: .page, query: "", title: "Launch video: the new thing", url: URL(string: "https://example.com/")).isVideo)
        #expect(!MemoryRecord(kind: .search, query: "youtube video").isVideo, "only pages are videos")
        #expect(!MemoryRecord(kind: .page, query: "go to youtube", title: "YouTube", url: URL(string: "https://m.youtube.com")).isVideo, "the front page is the site, not a video")
        #expect(!MemoryRecord(kind: .page, query: "", title: "YouTube", url: URL(string: "https://m.youtube.com/")).isVideo)
        #expect(MemoryRecord(kind: .page, query: "", title: "YouTube", url: URL(string: "https://m.youtube.com/shorts/a")).isVideo)
    }
}
