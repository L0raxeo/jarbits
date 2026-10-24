import Foundation
import Testing
@testable import Routing

@Suite struct QueryParserTests {
    @Test func imageResultsAreAResultsPageForTheSubject() throws {
        let url = QueryParser.imageSearchURL(for: "Dyson PencilVac")
        #expect(url.absoluteString == "https://www.google.com/search?q=Dyson%20PencilVac&tbm=isch")
        #expect(QueryParser.isSearchResults(url))
        #expect(QueryParser.searchTerm(in: url) == "Dyson PencilVac")
        #expect(QueryParser.displayText(for: url) == "Dyson PencilVac")
    }

    @Test func aPlusInAnImageSubjectSurvives() {
        let url = QueryParser.imageSearchURL(for: "c++ logo")
        #expect(url.absoluteString.contains("q=c%2B%2B%20logo&tbm=isch"))
        #expect(QueryParser.searchTerm(in: url) == "c++ logo")
    }
}

@Suite struct VideoSearchURLTests {
    @Test func videoResultsAreAResultsPageForTheTerm() {
        let url = QueryParser.videoSearchURL(for: "videos of Pele")
        #expect(url.absoluteString == "https://www.google.com/search?q=videos%20of%20Pele&tbm=vid")
        #expect(QueryParser.isSearchResults(url))
        #expect(QueryParser.searchTerm(in: url) == "videos of Pele")
    }
}
