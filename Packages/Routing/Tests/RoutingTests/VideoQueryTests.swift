import Foundation
import Testing
@testable import Routing

@Suite struct VideoQueryTests {
    @Test(arguments: [
        ("You'll pull up some videos of Pele.", "videos of Pele"),
        ("show me cat videos", "cat videos"),
        ("watch the dune part 3 trailer", "dune part 3 trailer"),
        ("can you play me a few pele highlights please", "pele highlights"),
        ("I want to watch the super bowl halftime show", "super bowl halftime show"),
        ("no not that, find me some lofi music videos", "lofi music videos"),
    ])
    func theTermIsWhatFollowsTheAsk(query: String, term: String) {
        #expect(VideoQuery.parse(query)?.term == term, Comment(rawValue: query))
        #expect(VideoQuery.term(for: query) == term)
    }

    @Test(arguments: ["videos of pele", "pele highlights", "dune part 3 trailer", "show me", "watch"])
    func aBareTermOrNothingLeftIsTheQueryItself(query: String) {
        #expect(VideoQuery.parse(query) == nil, Comment(rawValue: query))
        #expect(VideoQuery.term(for: query) == query)
    }
}
