import Foundation
import Testing
@testable import Evals
@testable import Engine
@testable import Answers

@Suite struct PlanCaseTests {
    @Test func aLineParsesAndNamesItself() throws {
        let line = """
        {"query": "open the dyson page from yesterday", "memories": [{"kind": "page", "title": "Dyson PencilVac | Dyson", "url": "https://www.dyson.com/pencilvac", "daysAgo": 1}], "facts": ["Lorcan is vegetarian"], "calls": [{"name": "open", "arguments": {"thing": "m1"}}], "note": "n"}
        """
        let cases = try PlanSet.parse(Data(line.utf8))
        let planCase = try #require(cases.first)
        #expect(planCase.calls == [PlanCase.ExpectedCall(name: "open", arguments: ["thing": "m1"])])
        #expect(planCase.name == "open the dyson page from yesterday knowing 1 with 1 memories")
        let record = try #require(planCase.memories?.first?.record(now: AnswerContext.example.now))
        #expect(record.kind == .page && record.url?.host() == "www.dyson.com")
        #expect(record.date == AnswerContext.example.now.addingTimeInterval(-86_400))
        #expect(planCase.memories?.first?.record(now: AnswerContext.example.now).id == record.id, "the id is fixed by the title, so the request bytes are stable")
        #expect(throws: EvalSetError.self) { try PlanSet.parse(Data(#"{"query": "x", "calls": []}"#.utf8)) }
    }

    @Test func theFirstRoundsCallsAreCheckedByNameThenByPinnedArguments() {
        let planCase = PlanCase(query: "open the dyson page", calls: [.init(name: "open", arguments: ["thing": "m1"])])
        #expect(PlanCheck.failures(planCase, calls: [("open", ["thing": "M1 "])]).isEmpty, "a handle compares loosely")
        let several = PlanCase(query: "show both", calls: [.init(name: "open", arguments: ["things": "n1, n2"])], failure: "x")
        #expect(PlanCheck.failures(several, calls: [("open", ["things": "n1, n2"])]).isEmpty, "a list of handles reads joined")
        #expect(several.name == "show both after a failure")
        #expect(PlanCheck.failures(planCase, calls: [("open", ["thing": "m1"]), ("done", [:])]).isEmpty, "a trailing done is fine")
        #expect(PlanCheck.failures(planCase, calls: [("open", ["thing": "m2"])]) == ["open.thing: expected \"m1\", got \"m2\""])
        #expect(PlanCheck.failures(planCase, calls: [("web_results", ["query": "dyson"])]) == ["calls: expected open, got web_results"])
        #expect(PlanCheck.failures(planCase, calls: []) == ["calls: expected open, got none"])
        let either = PlanCase(query: "no not this one", calls: [.init(name: "site|ask")])
        #expect(PlanCheck.failures(either, calls: [("ask", ["question": "q"])]).isEmpty && PlanCheck.failures(either, calls: [("site", [:])]).isEmpty)
        #expect(PlanCheck.failures(either, calls: [("web_results", [:])]) == ["calls: expected site|ask, got web_results"])
        let two = PlanCase(query: "remember then suggest", calls: [.init(name: "remember"), .init(name: "narrative")])
        #expect(PlanCheck.failures(two, calls: [("remember", ["fact": "f"]), ("narrative", ["query": "q"])]).isEmpty)
        #expect(PlanCheck.failures(two, calls: [("remember", ["fact": "f"])]) == ["calls: expected remember, narrative, got remember"])
    }

    @Test func theRequestListsThingsWithHandlesAndIsStable() throws {
        let planCase = PlanCase(
            query: "compare this page with the dyson one",
            exchanges: [.page(query: "lifesteal", title: "My Base was GRIEFED", address: URL(string: "https://m.youtube.com/watch?v=abc")!)],
            memories: [.init(kind: .page, title: "Dyson PencilVac | Dyson", url: URL(string: "https://www.dyson.com/pencilvac"), daysAgo: 1)],
            calls: [.init(name: "narrative")]
        )
        let request = PlanRunner.request(for: planCase)
        let input = try #require(request.transcript?.first.flatMap { step -> String? in if case let .userText(text) = step { text } else { nil } })
        #expect(input.contains("- p1: Read \"My Base was GRIEFED\" (m.youtube.com)"))
        #expect(input.contains("- m1: A page from yesterday (www.dyson.com): \"Dyson PencilVac | Dyson\""))
        #expect(try PlanCache.key(for: request) == PlanCache.key(for: PlanRunner.request(for: planCase)), "the same case keys the same file")
        #expect(request.systemInstruction.hasPrefix(Persona.example.identityLine))
    }
}
