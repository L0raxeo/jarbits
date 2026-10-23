import Foundation
import Testing
@testable import Routing

@Suite struct MemorySearchTests {
    private func record(_ kind: MemoryRecord.Kind, _ query: String, title: String? = nil, url: String? = nil, text: String? = nil, daysAgo: Double = 0) -> MemoryRecord {
        MemoryRecord(
            date: Date(timeIntervalSinceNow: -daysAgo * 86_400),
            kind: kind, query: query, title: title, url: url.flatMap(URL.init(string:)), text: text
        )
    }

    @Test func termsDropTheRecallPhrasing() {
        #expect(MemorySearch.terms(from: "remember that convo on the dyson pencilvac") == ["dyson", "pencilvac"])
        #expect(MemorySearch.terms(from: "where's my grocery list") == ["grocery", "list"])
        #expect(MemorySearch.terms(from: "pull up that YouTube page from earlier") == ["youtube"])
        #expect(MemorySearch.terms(from: "go back to the reddit thread") == ["reddit", "thread"])
        #expect(MemorySearch.terms(from: "pull up that video about muse I was watching") == ["muse"])
    }

    @Test func aPageAnswersToItsOwnTitleNotTheSearchBeforeIt() {
        // The first page after a search carries the search; the next one browsed to does not.
        let first = record(.page, "rick steves europe", title: "Rick Steves' Europe: Lisbon", url: "https://m.youtube.com/watch?v=a", daysAgo: 1)
        let next = record(.page, "", title: "The Biggest Launch Since ChatGPT (Muse)", url: "https://m.youtube.com/watch?v=b")
        #expect(MemorySearch.matches([first, next], query: "pull up a video about rick steves") == [first])
        #expect(MemorySearch.matches([first, next], query: "pull up the video I was watching about muse") == [next])
    }

    @Test func theKindAndTimeWordsFindTheVideoNotTheWordCan() {
        let now = Date()
        let video = MemoryRecord(date: now.addingTimeInterval(-86_400), kind: .page, query: "", title: "Rick Steves' Europe: Lisbon", url: URL(string: "https://m.youtube.com/watch?v=a"))
        let recipe = MemoryRecord(date: now.addingTimeInterval(-3_600), kind: .narrative, query: "how do you make hot chocolate", text: "You can whisk cocoa into milk.")
        let microwave = MemoryRecord(date: now.addingTimeInterval(-3_000), kind: .search, query: "can you microwave chocolate milk")
        let water = MemoryRecord(date: now.addingTimeInterval(-2_000), kind: .search, query: "can you use water?")
        let all = [video, recipe, microwave, water]
        let query = "Can you pull up the videos I was watching yesterday"
        #expect(MemorySearch.terms(from: query).isEmpty, "\"can\" is phrasing, not a thing to find")
        #expect(MemorySearch.shortlist(all, query: query, now: now) == [video])
        #expect(MemorySearch.shortlist(all, query: "that chocolate thing", now: now) == [microwave, recipe], "no filter: word matches, newest first")
        #expect(MemorySearch.shortlist(all, query: "pull up what I was looking at", now: now).isEmpty, "no filter and no content word")
        #expect(MemorySearch.shortlist(all, query: "the answers from today", now: now) == [recipe], "a filter alone: the filtered set, newest first")
        #expect(MemorySearch.shortlist(all, query: "that chocolate search from today", now: now) == [microwave, water], "words first, then the rest of the filtered set")
    }

    @Test func aLaterTurnOfAConversationIsFound() {
        let thread = MemoryRecord(kind: .narrative, query: "how do you make hot chocolate", text: "Heat milk.", turns: [
            AnswerTurn(query: "how do you make hot chocolate", answer: "Heat milk."),
            AnswerTurn(query: "and with oat milk?", answer: "Oat milk scorches faster, so keep it under a simmer."),
        ])
        let other = record(.narrative, "capital of peru", text: "Lima.")
        #expect(MemorySearch.matches([other, thread], query: "that answer about oat milk") == [thread])
    }

    @Test func aNameSpeltNearlyRightStillMatches() {
        let hennessey = record(.page, "", title: "Hennessey Performance | Official Website", url: "https://www.hennesseyperformance.com/")
        let other = record(.page, "", title: "Henley Royal Regatta", url: "https://www.hrr.co.uk/")
        #expect(MemorySearch.matches([other, hennessey], query: "Pull up the website I was looking at about Hennessy.") == [hennessey])
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
        #expect(MemorySearch.matches([other, video], query: "pull up that video about muse I was watching") == [video])
    }

    @Test func nothingLeftMeansNoMatches() {
        let records = [record(.narrative, "is the dyson pencilvac worth it", text: "Yes.")]
        #expect(MemorySearch.matches(records, query: "pull that up again").isEmpty)
        #expect(MemorySearch.terms(from: "").isEmpty)
    }

    @Test func aNarrativeIsFoundByItsQuery() {
        let dyson = record(.narrative, "is the dyson pencilvac worth it", text: "It is light and ==quiet==.")
        let other = record(.narrative, "how is gingivitis healed", text: "Brushing.")
        #expect(MemorySearch.matches([other, dyson], query: "remember that convo on the dyson pencilvac") == [dyson])
    }

    @Test func aLongTermMatchesJoinedUpWords() {
        let dyson = record(.narrative, "dyson pencil vac review", text: "Fine.")
        #expect(MemorySearch.matches([dyson], query: "that pencilvac thing") == [dyson])
    }

    @Test func aPageIsFoundByItsHost() {
        let reddit = record(.page, "best mechanical keyboards reddit", title: "Which switches? : r/MechanicalKeyboards", url: "https://www.reddit.com/r/MechanicalKeyboards/comments/abc")
        let yt = record(.page, "lofi", title: "lofi hip hop radio", url: "https://m.youtube.com/watch?v=x")
        #expect(MemorySearch.matches([yt, reddit], query: "go back to that reddit thread") == [reddit])
        #expect(MemorySearch.matches([yt, reddit], query: "pull up that youtube page from earlier") == [yt])
    }

    @Test func everyTermBeatsSomeTerms() {
        let both = record(.narrative, "dyson pencilvac vs v15", text: "…", daysAgo: 5)
        let one = record(.narrative, "dyson v15 review", text: "…", daysAgo: 0)
        #expect(MemorySearch.matches([one, both], query: "remember the dyson pencilvac convo") == [both])
    }

    @Test func someTermsWhenNoneHasAll() {
        let a = record(.search, "dyson airwrap", daysAgo: 2)
        let b = record(.search, "shark vacuum", daysAgo: 1)
        #expect(MemorySearch.matches([a, b], query: "that dyson vacuum thing") == [b, a])
    }

    @Test func newestFirstAmongEquals() {
        let old = record(.narrative, "is the dyson pencilvac worth it", text: "…", daysAgo: 10)
        let new = record(.narrative, "is the dyson pencilvac worth it", text: "…", daysAgo: 1)
        #expect(MemorySearch.matches([old, new], query: "dyson pencilvac") == [new, old])
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
