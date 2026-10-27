import Foundation
import Testing
@testable import Evals
@testable import Routing

@Suite struct EvalCaseTests {
    @Test func aFullLineParses() throws {
        let line = """
        {"query": "why?", "exchanges": [{"query": "how do you make hot chocolate", "kind": "answer", "text": "Heat milk."}], "format": "narrative", "chain": 1, "pick": "one_line", "source": "continuation", "term": "t", "subject": "s", "site": "z", "note": "n"}
        """
        let cases = try EvalSet.parse(Data(line.utf8))
        let evalCase = try #require(cases.first)
        #expect(evalCase.query == "why?")
        #expect(evalCase.exchanges?.first?.text == "Heat milk.")
        #expect(evalCase.exchanges?.first?.kind == .answer)
        #expect(evalCase.format == .narrative)
        #expect(evalCase.chain == 1)
        #expect(evalCase.pick == .oneLine)
        #expect(evalCase.source == "continuation")
        #expect(evalCase.term == "t" && evalCase.subject == "s" && evalCase.site == "z" && evalCase.note == "n")
        #expect(evalCase.name == "why? after \"how do you make hot chocolate\"")
    }

    @Test func aPageExchangeParses() throws {
        let line = """
        {"query": "how big is it", "exchanges": [{"query": "brasil weather", "kind": "page", "title": "Weather in Brasília", "host": "weather.com", "address": "https://weather.com/br"}], "format": "narrative", "chain": 1}
        """
        let evalCase = try #require(try EvalSet.parse(Data(line.utf8)).first)
        #expect(evalCase.exchanges == [Exchange(query: "brasil weather", kind: .page, title: "Weather in Brasília", host: "weather.com", address: "https://weather.com/br")])
        #expect(evalCase.name == "how big is it after \"brasil weather\"")
    }

    @Test func aRecallExpectationParses() throws {
        let cases = try EvalSet.parse(Data("{\"query\": \"my recent searches\", \"format\": \"recall\", \"recall\": {\"kinds\": [\"searches\"], \"named\": false}}".utf8))
        #expect(cases[0].recall == RecallExpectation(kinds: [.searches], named: false, all: nil))
    }

    @Test func aMinimalLineParsesAndBlankLinesAreSkipped() throws {
        let cases = try EvalSet.parse(Data("\n{\"query\": \"news\", \"format\": \"web_results\"}\n\n".utf8))
        #expect(cases == [EvalCase(query: "news", format: .webResults)])
        #expect(cases[0].name == "news")
        #expect(cases[0].chain == nil, "any chain is accepted")
    }

    @Test func anOpenedSiteIsPartOfTheName() throws {
        let cases = try EvalSet.parse(Data("{\"query\": \"no not this one\", \"opened\": {\"name\": \"zillow\", \"host\": \"www.zillow.com\"}, \"format\": \"site\"}".utf8))
        #expect(cases[0].name == "no not this one over zillow")
        #expect(cases[0].opened == OpenedSite(name: "zillow", host: "www.zillow.com"))
    }

    @Test func anExchangeAndAnOpenedSiteMayCoexistAndTheSiteNamesTheCase() throws {
        let line = "{\"query\": \"no not this one\", \"exchanges\": [{\"query\": \"pull up zillow\", \"kind\": \"page\", \"title\": \"Zillow\", \"host\": \"www.zillow.com\", \"address\": \"https://www.zillow.com/\"}], \"opened\": {\"name\": \"zillow\", \"host\": \"www.zillow.com\"}, \"format\": \"site\"}"
        let cases = try EvalSet.parse(Data(line.utf8))
        #expect(cases[0].exchanges?.count == 1)
        #expect(cases[0].name == "no not this one over zillow", "the name a baseline from before the exchanges used")
    }

    @Test func aDuplicateNameIsAnErrorWithTheLine() {
        let data = Data("{\"query\": \"news\", \"format\": \"web_results\"}\n{\"query\": \"news\", \"format\": \"narrative\"}".utf8)
        #expect(throws: EvalSetError.duplicateName(line: 2, name: "news")) { try EvalSet.parse(data) }
    }

    @Test func anUnknownSourceIsAnError() {
        let data = Data("{\"query\": \"news\", \"format\": \"web_results\", \"source\": \"device\"}".utf8)
        #expect(throws: EvalSetError.unknownSource(line: 1, source: "device")) { try EvalSet.parse(data) }
        #expect(throws: EvalSetError.unknownSource(line: 1, source: "local:")) {
            try EvalSet.parse(Data("{\"query\": \"news\", \"format\": \"web_results\", \"source\": \"local:\"}".utf8))
        }
    }

    @Test func aMalformedLineNamesItself() {
        #expect(throws: EvalSetError.self) { try EvalSet.parse(Data("{\"query\": \"news\", \"format\": \"poster\"}".utf8)) }
        let oldThread = try? EvalSet.parse(Data("{\"query\": \"why?\", \"thread\": [{\"query\": \"q\", \"answer\": \"a\"}], \"format\": \"narrative\"}".utf8))
        #expect(oldThread?.first?.exchanges == nil, "a line in the old shape reads, with its thread ignored, so a stale baseline is not a crash")
    }

    @Test func sourceKindsReadAsOneWord() {
        #expect(RouteDecision.Source.local("time").kind == "local:time")
        #expect(RouteDecision.Source.error("timeout").kind == "error")
        #expect(RouteDecision.Source.confidenceFallback.kind == "confidenceFallback")
        for kind in RouteDecision.Source.kinds { #expect(RouteDecision.Source.isKind(kind)) }
        #expect(RouteDecision.Source.isKind("local:site"))
        #expect(!RouteDecision.Source.isKind("local"))
    }
}
