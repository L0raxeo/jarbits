import Foundation
import Testing
@testable import Evals
@testable import Engine

@Suite struct EvalCaseTests {
    @Test func aFullLineParses() throws {
        let line = """
        {"query": "why?", "exchanges": [{"query": "how do you make hot chocolate", "kind": "answer", "text": "Heat milk."}], "instinct": "narrative", "chain": 1, "pick": "one_line", "source": "jev", "term": "t", "subject": "s", "site": "z", "note": "n"}
        """
        let cases = try EvalSet.parse(Data(line.utf8))
        let evalCase = try #require(cases.first)
        #expect(evalCase.query == "why?")
        #expect(evalCase.exchanges?.first?.text == "Heat milk.")
        #expect(evalCase.exchanges?.first?.kind == .answer)
        #expect(evalCase.instinct == .narrative)
        #expect(evalCase.chain == 1)
        #expect(evalCase.pick == .oneLine)
        #expect(evalCase.source == "jev")
        #expect(evalCase.note == "n")
        #expect(evalCase.name == "why? after \"how do you make hot chocolate\"")
    }

    @Test func aPageExchangeParses() throws {
        let line = """
        {"query": "how big is it", "exchanges": [{"query": "brasil weather", "kind": "page", "title": "Weather in Brasília", "host": "weather.com", "address": "https://weather.com/br"}], "instinct": "narrative", "chain": 1}
        """
        let evalCase = try #require(try EvalSet.parse(Data(line.utf8)).first)
        #expect(evalCase.exchanges == [Exchange(query: "brasil weather", kind: .page, title: "Weather in Brasília", host: "weather.com", address: "https://weather.com/br")])
        #expect(evalCase.name == "how big is it after \"brasil weather\"")
    }

    @Test func aRecallExpectationParses() throws {
        let cases = try EvalSet.parse(Data("{\"query\": \"my recent searches\", \"instinct\": \"recall\", \"recall\": {\"kinds\": [\"searches\"], \"named\": false}}".utf8))
        #expect(cases[0].recall == RecallExpectation(kinds: [.searches], named: false, all: nil))
    }

    @Test func aMinimalLineParsesAndBlankLinesAreSkipped() throws {
        let cases = try EvalSet.parse(Data("\n{\"query\": \"news\", \"instinct\": \"web_results\"}\n\n".utf8))
        #expect(cases == [EvalCase(query: "news", instinct: .webResults)])
        #expect(cases[0].name == "news")
        #expect(cases[0].chain == nil, "any chain is accepted")
    }

    @Test func anOpenedSiteIsPartOfTheName() throws {
        let cases = try EvalSet.parse(Data("{\"query\": \"no not this one\", \"opened\": {\"name\": \"zillow\", \"host\": \"www.zillow.com\"}, \"instinct\": \"site\"}".utf8))
        #expect(cases[0].name == "no not this one over zillow")
        #expect(cases[0].opened == OpenedSite(name: "zillow", host: "www.zillow.com"))
    }

    @Test func anExchangeAndAnOpenedSiteMayCoexistAndTheSiteNamesTheCase() throws {
        let line = "{\"query\": \"no not this one\", \"exchanges\": [{\"query\": \"pull up zillow\", \"kind\": \"page\", \"title\": \"Zillow\", \"host\": \"www.zillow.com\", \"address\": \"https://www.zillow.com/\"}], \"opened\": {\"name\": \"zillow\", \"host\": \"www.zillow.com\"}, \"instinct\": \"site\"}"
        let cases = try EvalSet.parse(Data(line.utf8))
        #expect(cases[0].exchanges?.count == 1)
        #expect(cases[0].name == "no not this one over zillow", "the name a baseline from before the exchanges used")
    }

    @Test func aDuplicateNameIsAnErrorWithTheLine() {
        let data = Data("{\"query\": \"news\", \"instinct\": \"web_results\"}\n{\"query\": \"news\", \"instinct\": \"narrative\"}".utf8)
        #expect(throws: EvalSetError.duplicateName(line: 2, name: "news")) { try EvalSet.parse(data) }
    }

    @Test func anUnknownSourceIsAnError() {
        let data = Data("{\"query\": \"news\", \"instinct\": \"web_results\", \"source\": \"device\"}".utf8)
        #expect(throws: EvalSetError.unknownSource(line: 1, source: "device")) { try EvalSet.parse(data) }
        #expect(throws: EvalSetError.unknownSource(line: 1, source: "local:")) {
            try EvalSet.parse(Data("{\"query\": \"news\", \"instinct\": \"web_results\", \"source\": \"local:\"}".utf8))
        }
    }

    @Test func aMalformedLineNamesItself() {
        #expect(throws: EvalSetError.self) { try EvalSet.parse(Data("{\"query\": \"news\", \"instinct\": \"poster\"}".utf8)) }
        let oldThread = try? EvalSet.parse(Data("{\"query\": \"why?\", \"thread\": [{\"query\": \"q\", \"answer\": \"a\"}], \"instinct\": \"narrative\"}".utf8))
        #expect(oldThread?.first?.exchanges == nil, "a line in the old shape reads, with its thread ignored, so a stale baseline is not a crash")
    }

    @Test func sourceKindsReadAsOneWord() {
        #expect(Pick.Source.error("timeout").kind == "error")
        #expect(Pick.Source.confidenceFallback.kind == "confidenceFallback")
        #expect(Pick.Source.directURL.kind == "directURL")
        for kind in Pick.Source.kinds { #expect(Pick.Source.isKind(kind)) }
        #expect(!Pick.Source.isKind("local:site"), "version 1's device rules are gone")
        #expect(!Pick.Source.isKind("recencyFallback"), "no gate overrules a pick")
    }
}
