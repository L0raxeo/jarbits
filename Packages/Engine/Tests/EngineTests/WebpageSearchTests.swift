import Foundation
import Testing
@testable import Engine

/// Finding one of the open webpages by words, kind, time, count and
/// meaning order: the shortlist a recall judges.
@Suite struct WebpageSearchTests {
    private func page(_ title: String, _ url: String, query: String = "", daysAgo: Double = 0) -> Webpage {
        Webpage(kind: .page, address: URL(string: url)!, title: title, query: query, opened: Date(timeIntervalSinceNow: -daysAgo * 86_400))
    }

    private func search(_ term: String, daysAgo: Double = 0, minutesAgo: Double = 0) -> Webpage {
        Webpage(kind: .search, address: QueryParser.searchURL(for: term), query: term, opened: Date(timeIntervalSinceNow: -daysAgo * 86_400 - minutesAgo * 60))
    }

    @Test func aPageAnswersToItsOwnTitleNotTheSearchBeforeIt() {
        let first = page("Rick Steves' Europe: Lisbon", "https://m.youtube.com/watch?v=a", query: "rick steves europe", daysAgo: 1)
        let next = page("The Biggest Launch Since ChatGPT (Muse)", "https://m.youtube.com/watch?v=b")
        #expect(WebpageSearch.matches([first, next], topic: "rick steves") == [first])
        #expect(WebpageSearch.matches([first, next], topic: "muse") == [next])
    }

    @Test func theKindAndTimeWordsFindTheVideoNotTheWordCan() {
        let now = Date()
        let video = Webpage(kind: .page, address: URL(string: "https://m.youtube.com/watch?v=a")!, title: "Rick Steves' Europe: Lisbon", opened: now.addingTimeInterval(-86_400))
        let microwave = Webpage(kind: .search, address: QueryParser.searchURL(for: "can you microwave chocolate milk"), query: "can you microwave chocolate milk", opened: now.addingTimeInterval(-3_000))
        let water = Webpage(kind: .search, address: QueryParser.searchURL(for: "can you use water?"), query: "can you use water?", opened: now.addingTimeInterval(-2_000))
        let all = [video, microwave, water]
        let today = DateInterval(start: now.addingTimeInterval(-4_000), end: now)
        let yesterday = DateInterval(start: now.addingTimeInterval(-90_000), end: now.addingTimeInterval(-4_000))
        #expect(WebpageSearch.shortlist(all, topic: nil, ask: RecallAsk(intent: RecallIntent(kinds: [.videos], named: false, all: false), window: yesterday)) == [video])
        #expect(WebpageSearch.shortlist(all, topic: "chocolate") == [microwave], "no ask: word matches, newest first")
        #expect(WebpageSearch.shortlist(all, topic: nil).isEmpty, "no ask and no topic")
        #expect(WebpageSearch.shortlist(all, topic: nil, ask: RecallAsk(intent: RecallIntent(kinds: [.searches], named: false, all: false), window: today)) == [water, microwave], "an ask alone: the allowed set, newest first")
        #expect(WebpageSearch.shortlist(all, topic: "chocolate", ask: RecallAsk(intent: RecallIntent(kinds: [.searches], named: true, all: false), window: today)) == [microwave, water], "words first, then the rest of the allowed set")
        #expect(WebpageSearch.shortlist(all, topic: nil, ask: RecallAsk(intent: RecallIntent(kinds: [.answers], named: false, all: false))) == [water, microwave, video], "answers name nothing open: read as no kind")
    }

    @Test func theMeaningOrderLeadsTheShortlistWhenAThingIsNamed() {
        let now = Date()
        let hennessey = Webpage(kind: .page, address: URL(string: "https://www.hennesseyperformance.com/")!, title: "Hennessey Performance | Official Website", opened: now.addingTimeInterval(-86_400))
        let dyson = Webpage(kind: .page, address: URL(string: "https://www.dyson.com/pencilvac")!, title: "Dyson PencilVac | Dyson", query: "dyson pencilvac", opened: now.addingTimeInterval(-3_600))
        let cars = Webpage(kind: .search, address: QueryParser.searchURL(for: "fastest cars 2026"), query: "fastest cars 2026", opened: now.addingTimeInterval(-600))
        let all = [hennessey, dyson, cars]
        #expect(WebpageSearch.shortlist(all, topic: "car page") == [cars], "by words alone, only the search holds \"car\"")
        #expect(WebpageSearch.shortlist(all, topic: "car page", ranked: [hennessey.id, cars.id, dyson.id]) == [hennessey, cars, dyson], "the nearest first, then the word match, then the rest")
        let pages = RecallAsk(intent: RecallIntent(kinds: [.pages], named: true, all: false))
        #expect(WebpageSearch.shortlist(all, topic: "car page", ask: pages, ranked: [cars.id, hennessey.id]) == [hennessey, cars], "the kinds still filter the nearest; the words relaxed the kind, as before")
        #expect(WebpageSearch.shortlist(all, topic: "car page", ask: RecallAsk(intent: RecallIntent(named: false, all: false), count: 2), ranked: [hennessey.id]) == [cars, dyson], "a count is by recency, whatever the index says")
        #expect(WebpageSearch.shortlist(all, topic: nil, ask: pages, ranked: [hennessey.id]) == [dyson, hennessey], "nothing named: newest, whatever the index says")
        #expect(hennessey.indexText == "Hennessey Performance | Official Website\nwww.hennesseyperformance.com")
        #expect(cars.indexText == "fastest cars 2026\nwww.google.com", "a search is titled by its term, so it is not repeated")
        #expect(WebpageSearch.interleave([cars, dyson], [dyson, hennessey], limit: 5) == [cars, dyson, hennessey])
        #expect(WebpageSearch.interleave([cars], [dyson, hennessey], limit: 2) == [cars, dyson])
    }

    @Test func theKindWordIsAPreferenceNotAWall() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        let page = Webpage(kind: .page, address: URL(string: "https://www.dyson.com/pencilvac")!, title: "Dyson PencilVac | Dyson", query: "dyson pencilvac", opened: now.addingTimeInterval(-300))
        let search = Webpage(kind: .search, address: QueryParser.searchURL(for: "Can you show me a picture of the Dyson PencilVac"), query: "Can you show me a picture of the Dyson PencilVac", opened: now.addingTimeInterval(-600))
        let pictures = Webpage(kind: .images, address: QueryParser.imageSearchURL(for: "gingivitis"), query: "gingivitis", opened: now.addingTimeInterval(-7200))
        let all = [page, search, pictures]
        let everything = RecallAsk(intent: RecallIntent(kinds: [], named: true, all: true))
        #expect(WebpageSearch.shortlist(all, topic: "dyson pencilvac", ask: everything) == [page, search], "the pages and searches that hold the words")
        let picturesOnly = RecallAsk(intent: RecallIntent(kinds: [.pictures], named: true, all: false))
        #expect(WebpageSearch.shortlist(all, topic: "gingivitis", ask: picturesOnly) == [pictures], "a picture search that holds the words is preferred")
        #expect(WebpageSearch.shortlist(all, topic: "dyson", ask: picturesOnly) == [page, search], "the kind was wrong: the pages that hold the words")
        let lastWeek = DateInterval(start: now.addingTimeInterval(-14 * 86_400), end: now.addingTimeInterval(-7 * 86_400))
        #expect(WebpageSearch.shortlist(all, topic: "dyson", ask: RecallAsk(intent: RecallIntent(kinds: [.pages], named: true, all: false), window: lastWeek)).isEmpty, "the span is never relaxed")
    }

    @Test func everythingAboutSomethingIgnoresTheKindWords() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        let page = Webpage(kind: .page, address: URL(string: "https://www.dyson.com/pencilvac")!, title: "Dyson PencilVac | Dyson", query: "dyson pencilvac", opened: now.addingTimeInterval(-300))
        let search = Webpage(kind: .search, address: QueryParser.searchURL(for: "Can you show me a picture of the Dyson PencilVac"), query: "Can you show me a picture of the Dyson PencilVac", opened: now.addingTimeInterval(-600))
        let old = Webpage(kind: .page, address: URL(string: "https://example.com/v15")!, title: "Dyson V15 review", query: "dyson v15", opened: now.addingTimeInterval(-10 * 86_400))
        let other = Webpage(kind: .search, address: QueryParser.searchURL(for: "capital of peru"), query: "capital of peru", opened: now.addingTimeInterval(-100))
        let all = [page, search, old, other]
        let everything = RecallAsk(intent: RecallIntent(kinds: [], named: true, all: true))
        #expect(WebpageSearch.shortlist(all, topic: "dyson", ask: everything) == [page, search, old], "every kind, word matches, newest first")
        let today = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        #expect(WebpageSearch.shortlist(all, topic: "dyson", ask: RecallAsk(intent: RecallIntent(kinds: [], named: true, all: true), window: today)) == [page, search], "the span still holds")
        #expect(WebpageSearch.shortlist(all, topic: nil).isEmpty, "nothing to go on")
    }

    @Test func aCountIsTheNewestSoManyOfTheKindsNamed() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        func search(_ term: String, minutesAgo: Int) -> Webpage {
            Webpage(kind: .search, address: QueryParser.searchURL(for: term), query: term, opened: now.addingTimeInterval(-Double(minutesAgo) * 60))
        }
        let s1 = search("alternatives to dyson", minutesAgo: 30)
        let s2 = search("dyson pencilvac", minutesAgo: 5)
        let s3 = search("flights to lima", minutesAgo: 400)
        let p1 = Webpage(kind: .page, address: URL(string: "https://www.reddit.com/")!, title: "Reddit", query: "reddit", opened: now.addingTimeInterval(-600))
        let all = [s1, s2, s3, p1]
        func ask(_ kinds: Set<RecallIntent.Kind>, named: Bool, count: Int) -> RecallAsk {
            RecallAsk(intent: RecallIntent(kinds: kinds, named: named, all: false), count: count)
        }
        #expect(WebpageSearch.shortlist(all, topic: nil, ask: ask([.searches], named: false, count: 2)) == [s2, s1], "newest first, that many, searches only")
        #expect(WebpageSearch.shortlist(all, topic: nil, ask: ask([], named: false, count: 3)) == [s2, p1, s1], "no kind: everything")
        #expect(WebpageSearch.shortlist(all, topic: "dyson", ask: ask([.searches], named: true, count: 2)) == [s2, s1], "a topic narrows the pool")
        #expect(WebpageSearch.shortlist(all, topic: "lima", ask: ask([.searches], named: true, count: 2)) == [s3])
        #expect(WebpageSearch.shortlist(all, topic: nil, ask: ask([.pictures], named: false, count: 5)).isEmpty)
        let insta = Webpage(kind: .page, address: URL(string: "https://www.instagram.com/")!, title: "Instagram", query: "open insta", opened: now.addingTimeInterval(-2000 * 60))
        #expect(WebpageSearch.shortlist(all + [insta], topic: nil, ask: ask([], named: false, count: 5)) == [s2, p1, s1, s3, insta], "no topic: the newest five")
        #expect(RecallAsk(intent: RecallIntent(kinds: [.searches], named: false, all: false), count: 5).countTitle == "Last 5 searches")
        #expect(RecallAsk(intent: RecallIntent(kinds: [], named: false, all: true)).allTitle == "All webpages")
        #expect(RecallAsk(intent: RecallIntent(kinds: [.videos], named: false, all: true)).allTitle == "All videos")
    }

    @Test func theTermsAreTheTopicsWords() {
        #expect(WebpageSearch.terms(of: "Dyson PencilVac") == ["dyson", "pencilvac"])
        #expect(WebpageSearch.terms(of: "Macy's page") == ["macys", "page"], "apostrophes join, as a page's own words do")
        #expect(WebpageSearch.terms(of: nil).isEmpty && WebpageSearch.terms(of: "").isEmpty)
    }

    @Test func aNameSpeltNearlyRightStillMatches() {
        let hennessey = page("Hennessey Performance | Official Website", "https://www.hennesseyperformance.com/")
        let other = page("Henley Royal Regatta", "https://www.hrr.co.uk/")
        #expect(WebpageSearch.matches([other, hennessey], topic: "Hennessy") == [hennessey])
        #expect(WebpageSearch.close("hennessy", "hennessey"))
        #expect(WebpageSearch.close("steves", "steve"))
        #expect(!WebpageSearch.close("muse", "mouse"), "short words must match exactly")
        #expect(!WebpageSearch.close("henley", "hennessey"))
    }

    @Test func trackingCodesDoNotMakeANewPage() throws {
        let tapped = try #require(URL(string: "https://www.hennesseyperformance.com/?srsltid=AYCX9vLu&utm_source=google#top"))
        #expect(Webpage.canonical(tapped).absoluteString == "https://www.hennesseyperformance.com/")
        let video = try #require(URL(string: "https://m.youtube.com/watch?v=abc&t=10"))
        #expect(Webpage.canonical(video).absoluteString == "https://m.youtube.com/watch?v=abc&t=10")
        #expect(Webpage(kind: .page, address: tapped).address.absoluteString == "https://www.hennesseyperformance.com/", "a page is kept by its canonical address")
    }

    @Test func aVideoIsFoundByItsTitleOrItsHost() {
        let video = page("The Biggest Launch Since ChatGPT (Muse)", "https://m.youtube.com/watch?v=abc", query: "cleo abram")
        let other = page("lofi hip hop radio", "https://m.youtube.com/watch?v=x", query: "lofi")
        #expect(WebpageSearch.matches([other, video], topic: "muse") == [video])
        #expect(video.isVideo && other.isVideo)
        #expect(!page("YouTube", "https://m.youtube.com/").isVideo, "a video host's front page is the site, not a video")
        #expect(page("How to cook a video tutorial", "https://example.com/t").isVideo, "titled as a video")
    }

    @Test func aPageIsFoundByItsHostAndAJoinedTermMatches() {
        let reddit = page("Which switches? : r/MechanicalKeyboards", "https://www.reddit.com/r/MechanicalKeyboards/comments/abc", query: "best mechanical keyboards reddit")
        let yt = page("lofi hip hop radio", "https://m.youtube.com/watch?v=x", query: "lofi")
        #expect(WebpageSearch.matches([yt, reddit], topic: "reddit thread") == [reddit])
        #expect(WebpageSearch.matches([yt, reddit], topic: "youtube") == [yt])
        let dyson = search("dyson pencil vac review")
        #expect(WebpageSearch.matches([dyson], topic: "pencilvac") == [dyson])
        #expect(WebpageSearch.matches([dyson], topic: nil).isEmpty && WebpageSearch.matches([dyson], topic: "").isEmpty)
    }

    @Test func everyTermBeatsSomeTermsAndNewestWinsAmongEquals() {
        let both = search("dyson pencilvac vs v15", daysAgo: 5)
        let one = search("dyson v15 review", daysAgo: 0)
        #expect(WebpageSearch.matches([one, both], topic: "dyson pencilvac") == [both])
        let a = search("dyson airwrap", daysAgo: 2)
        let b = search("shark vacuum", daysAgo: 1)
        #expect(WebpageSearch.matches([a, b], topic: "dyson vacuum") == [b, a])
        let old = search("is the dyson pencilvac worth it", daysAgo: 10)
        let new = search("is the dyson pencilvac worth it", daysAgo: 1)
        #expect(WebpageSearch.matches([old, new], topic: "dyson pencilvac") == [new, old])
    }

    @Test func sameThing() {
        let a = page("a", "https://example.com/a", query: "x")
        let b = page("b", "https://example.com/a?utm_source=x", query: "y")
        let c = page("c", "https://example.com/c", query: "x")
        #expect(a.sameThing(as: b), "the same address, tracking aside")
        #expect(!a.sameThing(as: c))
        #expect(search("Dyson").sameThing(as: search("dyson")))
        #expect(!search("dyson").sameThing(as: Webpage(kind: .images, address: QueryParser.imageSearchURL(for: "dyson"), query: "dyson")))
    }
}
