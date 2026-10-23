import Foundation
import Testing
@testable import Routing

@Suite struct SearchQueryTests {
    @Test(arguments: [
        ("search for steve jobs", "steve jobs"),
        ("search up the eiffel tower", "the eiffel tower"),
        ("look up flights to lima", "flights to lima"),
        ("lookup chocolate milk", "chocolate milk"),
        ("search google for best laptops 2026", "best laptops 2026"),
        ("search the web for python tutorials", "python tutorials"),
        ("search the internet for hiking boots", "hiking boots"),
        ("do a google search for capybaras", "capybaras"),
        ("do a web search for capybaras", "capybaras"),
        ("do a search for capybaras", "capybaras"),
        ("google search for capybaras", "capybaras"),
        ("web search for capybaras", "capybaras"),
        ("web search capybaras", "capybaras"),
    ])
    func eachVerbIsACommandAndLeavesTheTerm(query: String, term: String) {
        let parsed = SearchQuery.parse(query)
        #expect(parsed?.term == term, "\(query)")
        #expect(parsed?.isCommand == true, "\(query)")
    }

    @Test(arguments: [
        ("can you look up steve jobs", "steve jobs"),
        ("hey google steve jobs", "steve jobs"),
        ("ok just search for steve jobs please", "steve jobs"),
    ])
    func leadsComeOffWithTheOpener(query: String, term: String) {
        #expect(SearchQuery.parse(query)?.term == term, "\(query)")
    }

    @Test func googleIsAVerbButNotACommand() {
        let parsed = SearchQuery.parse("google steve jobs")
        #expect(parsed?.term == "steve jobs")
        #expect(parsed?.isCommand == false)
    }

    @Test func theTermIsKeptAsTyped() {
        #expect(SearchQuery.parse("Google Steve Jobs?")?.term == "Steve Jobs?")
        #expect(SearchQuery.parse("Google: Steve Jobs")?.term == "Steve Jobs")
        #expect(SearchQuery.parse("look up what's new in Swift 6")?.term == "what's new in Swift 6")
        #expect(SearchQuery.parse("search for café in Lyon")?.term == "café in Lyon")
    }

    @Test(arguments: ["google maps", "google stock", "google docs", "google maps directions to boston", "google earnings call", "google translate"])
    func aGoogleProductIsTheCompanysName(query: String) {
        #expect(SearchQuery.parse(query) == nil, "\(query)")
        #expect(SearchQuery.term(for: query) == query)
    }

    @Test(arguments: ["google", "search for", "look up", "please", "best laptops 2026", "chocolate milk", "search engine optimization", "steve jobs"])
    func aQueryThatNamesNoSearchIsLeftAlone(query: String) {
        #expect(SearchQuery.parse(query) == nil, "\(query)")
        #expect(SearchQuery.term(for: query) == query)
    }

    @Test func trailersComeOffWithOrWithoutAnOpener() {
        let onGoogle = SearchQuery.parse("steve jobs on google")
        #expect(onGoogle?.term == "steve jobs")
        #expect(onGoogle?.isCommand == false)
        #expect(SearchQuery.parse("look up steve jobs for me please")?.term == "steve jobs")
        #expect(SearchQuery.parse("google steve jobs please")?.term == "steve jobs")
    }

    @Test func theSearchTermOfAResultsPageIsItsQuery() {
        let url = QueryParser.searchURL(for: "steve jobs")
        #expect(QueryParser.searchTerm(in: url) == "steve jobs")
        #expect(QueryParser.searchTerm(in: URL(string: "https://www.google.com/search?hl=en&q=steve+jobs&oq=x")!) == "steve jobs")
        #expect(QueryParser.searchTerm(in: QueryParser.searchURL(for: "c++ vs rust")) == "c++ vs rust", "a literal plus is percent-encoded and survives")
        #expect(QueryParser.searchTerm(in: URL(string: "https://www.google.com/")!) == nil)
        #expect(QueryParser.searchTerm(in: URL(string: "https://www.apple.com/search?q=mac")!) == nil, "only a Google results page")
    }
}
