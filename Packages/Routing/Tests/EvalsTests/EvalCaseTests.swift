import Foundation
import Testing
@testable import Evals
@testable import Routing

@Suite struct EvalCaseTests {
    @Test func aFullLineParses() throws {
        let line = """
        {"query": "why?", "thread": [{"query": "how do you make hot chocolate", "answer": "Heat milk."}], "format": "narrative", "pick": "one_line", "source": "continuation", "term": "t", "subject": "s", "site": "z", "note": "n"}
        """
        let cases = try EvalSet.parse(Data(line.utf8))
        let evalCase = try #require(cases.first)
        #expect(evalCase.query == "why?")
        #expect(evalCase.thread?.first?.answer == "Heat milk.")
        #expect(evalCase.thread?.first?.format == .narrative, "a turn without a format reads as narrative")
        #expect(evalCase.format == .narrative)
        #expect(evalCase.pick == .oneLine)
        #expect(evalCase.source == "continuation")
        #expect(evalCase.term == "t" && evalCase.subject == "s" && evalCase.site == "z" && evalCase.note == "n")
        #expect(evalCase.name == "why? after \"how do you make hot chocolate\"")
    }

    @Test func aRecallExpectationParses() throws {
        let cases = try EvalSet.parse(Data("{\"query\": \"my recent searches\", \"format\": \"recall\", \"recall\": {\"kinds\": [\"searches\"], \"named\": false}}".utf8))
        #expect(cases[0].recall == RecallExpectation(kinds: [.searches], named: false, all: nil))
    }

    @Test func aMinimalLineParsesAndBlankLinesAreSkipped() throws {
        let cases = try EvalSet.parse(Data("\n{\"query\": \"news\", \"format\": \"web_results\"}\n\n".utf8))
        #expect(cases == [EvalCase(query: "news", format: .webResults)])
        #expect(cases[0].name == "news")
    }

    @Test func anOpenedSiteIsPartOfTheName() throws {
        let cases = try EvalSet.parse(Data("{\"query\": \"no not this one\", \"opened\": {\"name\": \"zillow\", \"host\": \"www.zillow.com\"}, \"format\": \"site\"}".utf8))
        #expect(cases[0].name == "no not this one over zillow")
        #expect(cases[0].opened == OpenedSite(name: "zillow", host: "www.zillow.com"))
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

    @Test func aThreadAndAnOpenedSiteNeverCoexist() {
        let data = Data("{\"query\": \"why?\", \"thread\": [{\"query\": \"q\", \"answer\": \"a\"}], \"opened\": {\"name\": \"zillow\", \"host\": \"www.zillow.com\"}, \"format\": \"site\"}".utf8)
        #expect(throws: EvalSetError.threadAndOpened(line: 1)) { try EvalSet.parse(data) }
    }

    @Test func aMalformedLineNamesItself() {
        #expect(throws: EvalSetError.self) { try EvalSet.parse(Data("{\"query\": \"news\", \"format\": \"poster\"}".utf8)) }
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
