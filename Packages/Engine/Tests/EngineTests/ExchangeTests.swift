import Foundation
import Testing
@testable import Engine

@Suite struct ExchangeTests {
    private func keys(_ exchange: Exchange) throws -> Set<String> {
        let json = try #require(JSONSerialization.jsonObject(with: try JSONEncoder().encode(exchange)) as? [String: Any])
        return Set(json.keys)
    }

    @Test func eachKindCarriesOnlyWhatItHas() throws {
        #expect(try keys(.answer(query: "q", text: "a")) == ["query", "kind", "text"])
        let page = Exchange.page(query: "q", title: "Zillow", address: URL(string: "https://www.zillow.com/homes")!)
        #expect(try keys(page) == ["query", "kind", "title", "host", "address"])
        #expect(page.host == "www.zillow.com")
        #expect(page.address == "https://www.zillow.com/homes")
        #expect(try keys(.search(query: "q", term: "t")) == ["query", "kind", "text"])
        #expect(try keys(.picture(query: "q", subject: "eiffel tower")) == ["query", "kind", "text"])
        #expect(try keys(.picture(query: "q", subject: "eiffel tower", title: "Eiffel Tower")) == ["query", "kind", "title", "text"])
        #expect(try keys(.recall(query: "q", title: "Last 5 searches", titles: ["a", "b"])) == ["query", "kind", "title", "text"])
        #expect(try keys(.recall(query: "q", title: nil, titles: [])) == ["query", "kind"])
        #expect(try keys(.site(query: "q", name: "zillow", hosts: ["www.zillow.com"])) == ["query", "kind", "title", "text"])
    }

    @Test func turnsBecomeAnswerExchanges() {
        let turns = [AnswerTurn(query: "capital of peru", answer: "==Lima==", format: .oneLine), AnswerTurn(query: "and chile?", answer: "==Santiago==", format: .oneLine)]
        let exchanges = Exchange.fromTurns(turns)
        #expect(exchanges.map(\.query) == ["capital of peru", "and chile?"])
        #expect(exchanges.map(\.text) == ["==Lima==", "==Santiago=="])
        #expect(exchanges.allSatisfy { $0.kind == .answer })
    }

    @Test func theSummaryNamesWhatWasGot() {
        #expect(Exchange.answer(query: "q", text: "a").summary == "a written answer")
        #expect(Exchange.page(query: "q", title: "Weather in Brasília", address: URL(string: "https://weather.com/br")!).summary == "the page \"Weather in Brasília\" on weather.com")
        #expect(Exchange.search(query: "q", term: "brasil weather").summary == "web results for \"brasil weather\"")
        #expect(Exchange.picture(query: "q", subject: "eiffel tower").summary == "a picture of \"eiffel tower\"")
        #expect(Exchange.recall(query: "q", title: nil, titles: []).summary == "a grid of earlier memories")
        #expect(Exchange.site(query: "q", name: "zillow", hosts: []).summary == "a choice of sites for \"zillow\"")
    }

    @Test func anExchangeRoundTripsAndReadsALineWithoutOptionals() throws {
        let page = Exchange.page(query: "q", title: "T", address: URL(string: "https://a.b/c")!)
        #expect(try JSONDecoder().decode(Exchange.self, from: JSONEncoder().encode(page)) == page)
        let bare = try JSONDecoder().decode(Exchange.self, from: Data(#"{"query":"q","kind":"search"}"#.utf8))
        #expect(bare == Exchange(query: "q", kind: .search))
    }
}
