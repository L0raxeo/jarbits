import Foundation
import Testing
@testable import Engine

@Suite struct MemorySearchTests {
    private func record(_ kind: MemoryRecord.Kind, _ query: String, title: String? = nil, url: String? = nil, text: String? = nil, daysAgo: Double = 0) -> MemoryRecord {
        MemoryRecord(
            date: Date(timeIntervalSinceNow: -daysAgo * 86_400),
            kind: kind, query: query, title: title, url: url.flatMap(URL.init(string:)), text: text
        )
    }

    @Test func aPageAnswersToItsOwnTitleNotTheSearchBeforeIt() {
        // The first page after a search carries the search; the next one browsed to does not.
        let first = record(.page, "rick steves europe", title: "Rick Steves' Europe: Lisbon", url: "https://m.youtube.com/watch?v=a", daysAgo: 1)
        let next = record(.page, "", title: "The Biggest Launch Since ChatGPT (Muse)", url: "https://m.youtube.com/watch?v=b")
        #expect(MemorySearch.matches([first, next], topic: "rick steves") == [first])
        #expect(MemorySearch.matches([first, next], topic: "muse") == [next])
    }

    @Test func theKindAndTimeWordsFindTheVideoNotTheWordCan() {
        let now = Date()
        let video = MemoryRecord(date: now.addingTimeInterval(-86_400), kind: .page, query: "", title: "Rick Steves' Europe: Lisbon", url: URL(string: "https://m.youtube.com/watch?v=a"))
        let recipe = MemoryRecord(date: now.addingTimeInterval(-3_600), kind: .narrative, query: "how do you make hot chocolate", text: "You can whisk cocoa into milk.")
        let microwave = MemoryRecord(date: now.addingTimeInterval(-3_000), kind: .search, query: "can you microwave chocolate milk")
        let water = MemoryRecord(date: now.addingTimeInterval(-2_000), kind: .search, query: "can you use water?")
        let all = [video, recipe, microwave, water]
        let today = DateInterval(start: now.addingTimeInterval(-4_000), end: now)
        let yesterday = DateInterval(start: now.addingTimeInterval(-90_000), end: now.addingTimeInterval(-4_000))
        #expect(MemorySearch.shortlist(all, topic: nil, ask: RecallAsk(intent: RecallIntent(kinds: [.videos], named: false, all: false), window: yesterday)) == [video])
        #expect(MemorySearch.shortlist(all, topic: "chocolate") == [microwave, recipe], "no ask: word matches, newest first")
        #expect(MemorySearch.shortlist(all, topic: nil).isEmpty, "no ask and no topic")
        #expect(MemorySearch.shortlist(all, topic: nil, ask: RecallAsk(intent: RecallIntent(kinds: [.answers], named: false, all: false), window: today)) == [recipe], "an ask alone: the allowed set, newest first")
        #expect(MemorySearch.shortlist(all, topic: "chocolate", ask: RecallAsk(intent: RecallIntent(kinds: [.searches], named: true, all: false), window: today)) == [microwave, water], "words first, then the rest of the allowed set")
    }

    @Test func theMeaningOrderLeadsTheShortlistWhenAThingIsNamed() {
        let now = Date()
        let hennessey = MemoryRecord(date: now.addingTimeInterval(-86_400), kind: .page, query: "", title: "Hennessey Performance | Official Website", url: URL(string: "https://www.hennesseyperformance.com/"))
        let dyson = MemoryRecord(date: now.addingTimeInterval(-3_600), kind: .page, query: "dyson pencilvac", title: "Dyson PencilVac | Dyson", url: URL(string: "https://www.dyson.com/pencilvac"))
        let cars = MemoryRecord(date: now.addingTimeInterval(-600), kind: .search, query: "fastest cars 2026")
        let all = [hennessey, dyson, cars]
        #expect(MemorySearch.shortlist(all, topic: "car page") == [cars], "by words alone, only the search holds \"car\"")
        #expect(MemorySearch.shortlist(all, topic: "car page", ranked: [hennessey.id, cars.id, dyson.id]) == [hennessey, cars, dyson], "the nearest first, then the word match, then the rest")
        let pages = RecallAsk(intent: RecallIntent(kinds: [.pages], named: true, all: false))
        #expect(MemorySearch.shortlist(all, topic: "car page", ask: pages, ranked: [cars.id, hennessey.id]) == [hennessey, cars], "the kinds still filter the nearest; the words relaxed the kind, as before")
        #expect(MemorySearch.shortlist(all, topic: "car page", ask: RecallAsk(intent: RecallIntent(named: false, all: false), count: 2), ranked: [hennessey.id]) == [cars, dyson], "a count is by recency, whatever the index says")
        #expect(MemorySearch.shortlist(all, topic: nil, ask: pages, ranked: [hennessey.id]) == [dyson, hennessey], "nothing named: newest, whatever the index says")
        #expect(hennessey.indexText == "Hennessey Performance | Official Website\nwww.hennesseyperformance.com")
        #expect(MemoryRecord(date: now, kind: .narrative, query: "what is a venom f5", text: "A car.").indexText == "what is a venom f5\nA car.", "the title is the query, so it is not repeated")
        #expect(MemorySearch.interleave([cars, dyson], [dyson, hennessey], limit: 5) == [cars, dyson, hennessey])
        #expect(MemorySearch.interleave([cars], [dyson, hennessey], limit: 2) == [cars, dyson])
    }

    @Test func theKindWordIsAPreferenceNotAWall() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        let answer = MemoryRecord(date: now.addingTimeInterval(-7200), kind: .narrative, query: "how is gingivitis healed", text: "Remove the plaque.")
        let page = MemoryRecord(date: now.addingTimeInterval(-300), kind: .page, query: "dyson pencilvac", title: "Dyson PencilVac | Dyson", url: URL(string: "https://www.dyson.com/pencilvac"))
        let search = MemoryRecord(date: now.addingTimeInterval(-600), kind: .search, query: "Can you show me a picture of the Dyson PencilVac")
        let all = [answer, page, search]
        let everything = RecallAsk(intent: RecallIntent(kinds: [], named: true, all: true))
        #expect(MemorySearch.shortlist(all, topic: "dyson pencilvac", ask: everything) == [page, search], "no answer holds the words: the pages and searches that do")
        let answers = RecallAsk(intent: RecallIntent(kinds: [.answers], named: true, all: false))
        #expect(MemorySearch.shortlist(all, topic: "gingivitis", ask: answers) == [answer], "an answer that holds the words is still preferred")
        let lastWeek = DateInterval(start: now.addingTimeInterval(-14 * 86_400), end: now.addingTimeInterval(-7 * 86_400))
        #expect(MemorySearch.shortlist(all, topic: "dyson", ask: RecallAsk(intent: RecallIntent(kinds: [.answers], named: true, all: false), window: lastWeek)).isEmpty, "the span is never relaxed")
    }

    @Test func everythingAboutSomethingIgnoresTheKindWords() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        let answer = MemoryRecord(date: now.addingTimeInterval(-7200), kind: .narrative, query: "what are some alternatives to dyson", text: "Shark and Miele.")
        let page = MemoryRecord(date: now.addingTimeInterval(-300), kind: .page, query: "dyson pencilvac", title: "Dyson PencilVac | Dyson", url: URL(string: "https://www.dyson.com/pencilvac"))
        let search = MemoryRecord(date: now.addingTimeInterval(-600), kind: .search, query: "Can you show me a picture of the Dyson PencilVac")
        let old = MemoryRecord(date: now.addingTimeInterval(-10 * 86_400), kind: .page, query: "dyson v15", title: "Dyson V15 review", url: URL(string: "https://example.com/v15"))
        let other = MemoryRecord(date: now.addingTimeInterval(-100), kind: .narrative, query: "capital of peru", text: "Lima")
        let all = [answer, page, search, old, other]
        let everything = RecallAsk(intent: RecallIntent(kinds: [], named: true, all: true))
        #expect(MemorySearch.shortlist(all, topic: "dyson", ask: everything) == [page, search, answer, old], "every kind, word matches, newest first")
        let today = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        #expect(MemorySearch.shortlist(all, topic: "dyson", ask: RecallAsk(intent: RecallIntent(kinds: [], named: true, all: true), window: today)) == [page, search, answer], "the span still holds")
        #expect(MemorySearch.shortlist(all, topic: nil).isEmpty, "nothing to go on")
    }

    @Test func aCountIsTheNewestSoManyOfTheKindsNamed() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        func record(_ kind: MemoryRecord.Kind, _ query: String, minutesAgo: Int) -> MemoryRecord {
            MemoryRecord(date: now.addingTimeInterval(-Double(minutesAgo) * 60), kind: kind, query: query)
        }
        let s1 = record(.search, "alternatives to dyson", minutesAgo: 30)
        let s2 = record(.search, "dyson pencilvac", minutesAgo: 5)
        let s3 = record(.search, "flights to lima", minutesAgo: 400)
        let a1 = record(.narrative, "how is gingivitis healed", minutesAgo: 200)
        let p1 = record(.page, "reddit", minutesAgo: 10)
        let all = [s1, s2, s3, a1, p1]
        func ask(_ kinds: Set<RecallIntent.Kind>, named: Bool, count: Int) -> RecallAsk {
            RecallAsk(intent: RecallIntent(kinds: kinds, named: named, all: false), count: count)
        }
        #expect(MemorySearch.shortlist(all, topic: nil, ask: ask([.searches], named: false, count: 2)) == [s2, s1], "newest first, that many, searches only")
        #expect(MemorySearch.shortlist(all, topic: nil, ask: ask([.searches, .answers], named: false, count: 5)) == [s2, s1, a1, s3], "searches and answers, no pages")
        #expect(MemorySearch.shortlist(all, topic: nil, ask: ask([], named: false, count: 3)) == [s2, p1, s1], "no kind: everything")
        #expect(MemorySearch.shortlist(all, topic: "dyson", ask: ask([.searches], named: true, count: 2)) == [s2, s1], "a topic narrows the pool")
        #expect(MemorySearch.shortlist(all, topic: "lima", ask: ask([.searches], named: true, count: 2)) == [s3])
        #expect(MemorySearch.shortlist(all, topic: nil, ask: ask([.pictures], named: false, count: 5)).isEmpty)
        let insta = record(.page, "open insta", minutesAgo: 2000)
        let withInsta = all + [insta]
        #expect(MemorySearch.shortlist(withInsta, topic: nil, ask: ask([], named: false, count: 5)) == [s2, p1, s1, a1, s3], "no topic: the newest five")
    }

    @Test func theTermsAreTheTopicsWords() {
        #expect(MemorySearch.terms(of: "Dyson PencilVac") == ["dyson", "pencilvac"])
        #expect(MemorySearch.terms(of: "Macy's page") == ["macys", "page"], "apostrophes join, as the memory's own words do")
        #expect(MemorySearch.terms(of: nil).isEmpty && MemorySearch.terms(of: "").isEmpty)
    }

    @Test func aLaterTurnOfAConversationIsFound() {
        let thread = MemoryRecord(kind: .narrative, query: "how do you make hot chocolate", text: "Heat milk.", turns: [
            AnswerTurn(query: "how do you make hot chocolate", answer: "Heat milk."),
            AnswerTurn(query: "and with oat milk?", answer: "Oat milk scorches faster, so keep it under a simmer."),
        ])
        let other = record(.narrative, "capital of peru", text: "Lima.")
        #expect(MemorySearch.matches([other, thread], topic: "oat milk") == [thread])
        // A conversation that began with one line is a one-line record with turns, found the same way.
        let capitals = MemoryRecord(kind: .oneLine, query: "capital of peru", text: "==Lima==", turns: [
            AnswerTurn(query: "capital of peru", answer: "==Lima==", format: .oneLine),
            AnswerTurn(query: "and bolivia?", answer: "==Sucre== (La Paz is the seat of government)", format: .oneLine),
        ])
        #expect(MemorySearch.matches([thread, capitals], topic: "bolivia") == [capitals])
    }

    @Test func aNameSpeltNearlyRightStillMatches() {
        let hennessey = record(.page, "", title: "Hennessey Performance | Official Website", url: "https://www.hennesseyperformance.com/")
        let other = record(.page, "", title: "Henley Royal Regatta", url: "https://www.hrr.co.uk/")
        #expect(MemorySearch.matches([other, hennessey], topic: "Hennessy") == [hennessey])
        #expect(MemorySearch.close("hennessy", "hennessey"))
        #expect(MemorySearch.close("steves", "steve"))
        #expect(!MemorySearch.close("muse", "mouse"), "short words must match exactly")
        #expect(!MemorySearch.close("henley", "hennessey"))
    }

    @Test func trackingCodesDoNotMakeANewPage() throws {
        let tapped = try #require(URL(string: "https://www.hennesseyperformance.com/?srsltid=AYCX9vLu&utm_source=google#top"))
        #expect(MemoryRecord.canonical(tapped).absoluteString == "https://www.hennesseyperformance.com/")
        let video = try #require(URL(string: "https://m.youtube.com/watch?v=abc&t=10"))
        #expect(MemoryRecord.canonical(video).absoluteString == "https://m.youtube.com/watch?v=abc&t=10")
    }

    @Test func aVideoIsFoundByItsTitle() {
        let video = record(.page, "cleo abram", title: "The Biggest Launch Since ChatGPT (Muse)", url: "https://m.youtube.com/watch?v=abc")
        let other = record(.page, "lofi", title: "lofi hip hop radio", url: "https://m.youtube.com/watch?v=x")
        #expect(MemorySearch.matches([other, video], topic: "muse") == [video])
    }

    @Test func nothingLeftMeansNoMatches() {
        let records = [record(.narrative, "is the dyson pencilvac worth it", text: "Yes.")]
        #expect(MemorySearch.matches(records, topic: nil).isEmpty)
        #expect(MemorySearch.matches(records, topic: "").isEmpty)
    }

    @Test func aNarrativeIsFoundByItsQuery() {
        let dyson = record(.narrative, "is the dyson pencilvac worth it", text: "It is light and ==quiet==.")
        let other = record(.narrative, "how is gingivitis healed", text: "Brushing.")
        #expect(MemorySearch.matches([other, dyson], topic: "dyson pencilvac") == [dyson])
    }

    @Test func aLongTermMatchesJoinedUpWords() {
        let dyson = record(.narrative, "dyson pencil vac review", text: "Fine.")
        #expect(MemorySearch.matches([dyson], topic: "pencilvac") == [dyson])
    }

    @Test func aPageIsFoundByItsHost() {
        let reddit = record(.page, "best mechanical keyboards reddit", title: "Which switches? : r/MechanicalKeyboards", url: "https://www.reddit.com/r/MechanicalKeyboards/comments/abc")
        let yt = record(.page, "lofi", title: "lofi hip hop radio", url: "https://m.youtube.com/watch?v=x")
        #expect(MemorySearch.matches([yt, reddit], topic: "reddit thread") == [reddit])
        #expect(MemorySearch.matches([yt, reddit], topic: "youtube") == [yt])
    }

    @Test func everyTermBeatsSomeTerms() {
        let both = record(.narrative, "dyson pencilvac vs v15", text: "…", daysAgo: 5)
        let one = record(.narrative, "dyson v15 review", text: "…", daysAgo: 0)
        #expect(MemorySearch.matches([one, both], topic: "dyson pencilvac") == [both])
    }

    @Test func someTermsWhenNoneHasAll() {
        let a = record(.search, "dyson airwrap", daysAgo: 2)
        let b = record(.search, "shark vacuum", daysAgo: 1)
        #expect(MemorySearch.matches([a, b], topic: "dyson vacuum") == [b, a])
    }

    @Test func newestFirstAmongEquals() {
        let old = record(.narrative, "is the dyson pencilvac worth it", text: "…", daysAgo: 10)
        let new = record(.narrative, "is the dyson pencilvac worth it", text: "…", daysAgo: 1)
        #expect(MemorySearch.matches([old, new], topic: "dyson pencilvac") == [new, old])
    }

    @Test func sameThing() {
        let a = record(.page, "x", url: "https://example.com/a")
        let b = record(.page, "y", url: "https://example.com/a")
        let c = record(.page, "x", url: "https://example.com/c")
        #expect(a.sameThing(as: b))
        #expect(!a.sameThing(as: c))
        #expect(record(.search, "Dyson").sameThing(as: record(.search, "dyson")))
        #expect(!record(.search, "dyson").sameThing(as: record(.narrative, "dyson")))
    }
}
