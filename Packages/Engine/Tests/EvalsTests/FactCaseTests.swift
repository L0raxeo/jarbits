import Foundation
import Testing
@testable import Evals
@testable import Answers
@testable import Engine

@Suite struct FactCaseTests {
    @Test func casesParseAndAreNamed() throws {
        let data = Data("""
        {"query": "I'm vegetarian", "known": ["Lorcan is vegetarian."], "expect": [{"kind": "same", "of": 1}]}

        {"query": "I'm hungry", "expect": []}
        """.utf8)
        let cases = try FactSet.parse(data)
        #expect(cases.count == 2)
        #expect(cases[0].name == "I'm vegetarian knowing 1" && cases[1].name == "I'm hungry")
        #expect(throws: EvalSetError.self) { try FactSet.parse(Data(#"{"query": "x"}"#.utf8)) }
    }

    @Test func findingsAreMatchedAsASet() {
        let noah = FactCase(query: "story", expect: [.init(kind: .new, contains: ["Noah", "friend"]), .init(kind: .new, contains: ["vegan"])], allowMore: true)
        let found = [FactReader.Finding(text: "Lorcan's friend Noah declared himself vegan", kind: .new), FactReader.Finding(text: "Lorcan has a friend named Noah", kind: .new), FactReader.Finding(text: "Noah likes pizza", kind: .new)]
        #expect(FactCheck.failures(noah, findings: found).isEmpty, "order free, extras allowed")
        let strict = FactCase(query: "veg", known: ["Lorcan is vegetarian."], expect: [.init(kind: .same, of: 1)])
        #expect(FactCheck.failures(strict, findings: [FactReader.Finding(text: "Lorcan is vegetarian", kind: .same, of: 1)]).isEmpty)
        #expect(FactCheck.failures(strict, findings: [FactReader.Finding(text: "Lorcan is vegetarian", kind: .new)]) == ["expected a same fact of 1, none matched", "unexpected: new \"Lorcan is vegetarian\""])
        let nothing = FactCase(query: "hungry", expect: [])
        #expect(FactCheck.failures(nothing, findings: []).isEmpty)
        #expect(FactCheck.failures(nothing, findings: [FactReader.Finding(text: "Lorcan is hungry", kind: .new)]) == ["unexpected: new \"Lorcan is hungry\""])
        let request = FactRunner.request(for: strict)
        #expect(request.input.contains("Known facts:\n1. Lorcan is vegetarian.\nRequest: veg"))
    }
}
