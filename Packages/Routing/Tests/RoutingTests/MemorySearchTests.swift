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
