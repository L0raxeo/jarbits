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
        let today = DateInterval(start: now.addingTimeInterval(-4_000), end: now)
        let yesterday = DateInterval(start: now.addingTimeInterval(-90_000), end: now.addingTimeInterval(-4_000))
        #expect(MemorySearch.shortlist(all, query: query, ask: RecallAsk(intent: RecallIntent(kinds: [.videos], named: false, all: false), window: yesterday)) == [video])
        #expect(MemorySearch.shortlist(all, query: "that chocolate thing") == [microwave, recipe], "no ask: word matches, newest first")
        #expect(MemorySearch.shortlist(all, query: "pull up what I was looking at").isEmpty, "no ask and no content word")
        #expect(MemorySearch.shortlist(all, query: "the answers from today", ask: RecallAsk(intent: RecallIntent(kinds: [.answers], named: false, all: false), window: today)) == [recipe], "an ask alone: the allowed set, newest first")
        #expect(MemorySearch.shortlist(all, query: "that chocolate search from today", ask: RecallAsk(intent: RecallIntent(kinds: [.searches], named: true, all: false), window: today)) == [microwave, water], "words first, then the rest of the allowed set")
    }

    @Test func theKindWordIsAPreferenceNotAWall() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        let answer = MemoryRecord(date: now.addingTimeInterval(-7200), kind: .narrative, query: "how is gingivitis healed", text: "Remove the plaque.")
        let page = MemoryRecord(date: now.addingTimeInterval(-300), kind: .page, query: "dyson pencilvac", title: "Dyson PencilVac | Dyson", url: URL(string: "https://www.dyson.com/pencilvac"))
        let search = MemoryRecord(date: now.addingTimeInterval(-600), kind: .search, query: "Can you show me a picture of the Dyson PencilVac")
        let all = [answer, page, search]
        let everything = RecallAsk(intent: RecallIntent(kinds: [], named: true, all: true))
        #expect(MemorySearch.shortlist(all, query: "pull up everything we talked about with the dyson pencilvac", ask: everything) == [page, search], "no answer holds the words: the pages and searches that do")
        let answers = RecallAsk(intent: RecallIntent(kinds: [.answers], named: true, all: false))
        #expect(MemorySearch.shortlist(all, query: "what you told me about gingivitis", ask: answers) == [answer], "an answer that holds the words is still preferred")
        let lastWeek = DateInterval(start: now.addingTimeInterval(-14 * 86_400), end: now.addingTimeInterval(-7 * 86_400))
        #expect(MemorySearch.shortlist(all, query: "the answer about the dyson from last week", ask: RecallAsk(intent: RecallIntent(kinds: [.answers], named: true, all: false), window: lastWeek)).isEmpty, "the span is never relaxed")
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
        #expect(MemorySearch.shortlist(all, query: "pull up everything we talked about with the dyson", ask: everything) == [page, search, answer, old], "every kind, word matches, newest first")
        let today = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        #expect(MemorySearch.shortlist(all, query: "everything about the dyson from today", ask: RecallAsk(intent: RecallIntent(kinds: [], named: true, all: true), window: today)) == [page, search, answer], "the span still holds")
        #expect(MemorySearch.shortlist(all, query: "pull up everything").isEmpty, "nothing to go on")
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
        #expect(MemorySearch.shortlist(all, query: "pull up my last two searches", ask: ask([.searches], named: false, count: 2)) == [s2, s1], "newest first, that many, searches only")
        #expect(MemorySearch.shortlist(all, query: "the last 5 things I asked you, including google searches and ai stuff", ask: ask([.searches, .answers], named: false, count: 5)) == [s2, s1, a1, s3], "searches and answers, no pages")
        #expect(MemorySearch.shortlist(all, query: "my last 3 things", ask: ask([], named: false, count: 3)) == [s2, p1, s1], "no kind: everything")
        #expect(MemorySearch.shortlist(all, query: "my last 2 dyson searches", ask: ask([.searches], named: true, count: 2)) == [s2, s1], "a topic narrows the pool")
        #expect(MemorySearch.shortlist(all, query: "my last 2 lima searches", ask: ask([.searches], named: true, count: 2)) == [s3])
        #expect(MemorySearch.shortlist(all, query: "my last five pictures", ask: ask([.pictures], named: false, count: 5)).isEmpty)
        let insta = record(.page, "open insta", minutesAgo: 2000)
        let withInsta = all + [insta]
        #expect(MemorySearch.terms(from: "Can you pull up the last 5 things we were looking at").isEmpty, "all of it is asking")
        #expect(MemorySearch.shortlist(withInsta, query: "Can you pull up the last 5 things we were looking at", ask: ask([], named: false, count: 5)) == [s2, p1, s1, a1, s3], "no topic: the newest five, not whatever holds a word like \"were\"")
    }

    @Test func theTopicIsTheContentWordsAsTyped() {
        #expect(MemorySearch.topic(of: "Pull up everything we talked about with the Dyson PencilVac") == "Dyson PencilVac")
        #expect(MemorySearch.topic(of: "that thing about gingivitis again") == "gingivitis")
        #expect(MemorySearch.topic(of: "pull up what I was looking at") == "")
        #expect(MemorySearch.topic(of: "remember that convo on the dyson pencilvac") == "dyson pencilvac")
        #expect(MemorySearch.topic(of: "You'll pull up the last 5 things I asked you, like including Google searches and AI stuff, and all that") == "", "a contraction is one word, and the padding goes: nothing named, so nothing to search")
        #expect(MemorySearch.topic(of: "Pull up my last 5 queries") == "")
        #expect(MemorySearch.terms(from: "what's that Macy's page") == ["macys"], "apostrophes join, as the memory's own words do")
    }

    @Test func aLaterTurnOfAConversationIsFound() {
        let thread = MemoryRecord(kind: .narrative, query: "how do you make hot chocolate", text: "Heat milk.", turns: [
            AnswerTurn(query: "how do you make hot chocolate", answer: "Heat milk."),
            AnswerTurn(query: "and with oat milk?", answer: "Oat milk scorches faster, so keep it under a simmer."),
        ])
        let other = record(.narrative, "capital of peru", text: "Lima.")
        #expect(MemorySearch.matches([other, thread], query: "that answer about oat milk") == [thread])
        // A conversation that began with one line is a one-line record with turns, found the same way.
        let capitals = MemoryRecord(kind: .oneLine, query: "capital of peru", text: "==Lima==", turns: [
            AnswerTurn(query: "capital of peru", answer: "==Lima==", format: .oneLine),
            AnswerTurn(query: "and bolivia?", answer: "==Sucre== (La Paz is the seat of government)", format: .oneLine),
        ])
        #expect(MemorySearch.matches([thread, capitals], query: "that bolivia answer") == [capitals])
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
