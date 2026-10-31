import Foundation
import Testing
@testable import Answers
@testable import Engine

/// The fact reader's request: the rule, the numbered known facts, the list
/// schema, and how a reply's text becomes findings.
@Suite struct FactReaderTests {
    @Test func theInstructionStatesTheRuleAndTheThreeKinds() {
        let system = FactReader.system(.example)
        #expect(system.hasPrefix(Persona.example.identityLine + "\n"))
        #expect(system.contains("every lasting personal fact"))
        #expect(system.contains("It stays true whatever Lorcan happens to be working on, and could shape a later answer about anything"))
        #expect(system.contains("is a fact about that work, not about Lorcan, and gives nothing"), "a decision inside the work is not a fact about Lorcan")
        #expect(system.contains("\"Lorcan has a cofounder named Maya\" and nothing about the robot"), "the mixed case keeps the person and drops the work")
        #expect(system.contains("\"Lorcan has a friend named Noah\""))
        #expect(system.contains("already there in other words is same, with that fact's number"))
        #expect(system.contains("is changed, with that fact's number and the new words"))
        #expect(system.contains("Something true only now"))
        #expect(system.contains("points at something seen in this app"))
    }

    @Test func theSchemaIsAListOfFactsWithAKindAndANumber() throws {
        let schema = FactReader.schema(.example)
        let facts = try #require(schema["properties"]?["facts"])
        #expect(facts["type"]?.stringValue == "array")
        #expect(facts["items"]?["properties"]?["kind"]?["enum"]?.arrayValue?.compactMap(\.stringValue) == ["new", "same", "changed"])
        #expect(facts["items"]?["required"]?.arrayValue?.compactMap(\.stringValue) == ["text", "kind"])
        #expect(schema["required"]?.arrayValue?.compactMap(\.stringValue) == ["facts"])
    }

    @Test func theInputNumbersTheKnownFactsAndEndsOnTheRequest() {
        let known = FactReader.input(query: "I'm vegetarian", exchanges: [.answer(query: "q", text: "a")], known: ["Lorcan lives in Austin", "Lorcan's wife is Ana"])
        #expect(known == "Earlier: Asked \"q\" and got: a\nKnown facts:\n1. Lorcan lives in Austin\n2. Lorcan's wife is Ana\nRequest: I'm vegetarian")
        #expect(FactReader.input(query: "hi", exchanges: [], known: []) == "Known facts: none yet\nRequest: hi")
        let request = FactReader.request(query: "hi", exchanges: [], known: [], persona: .example)
        #expect(request.model == FactReader.model && request.maxOutputTokens == FactReader.maxOutputTokens)
    }

    @Test func aReplyBecomesFindingsAndANumberThatNamesNothingIsDropped() {
        let text = #"{"facts": [{"text": "Lorcan has a friend named Noah", "kind": "new", "of": null}, {"text": "Lorcan is vegetarian", "kind": "same", "of": 1}, {"text": "Lorcan eats fish", "kind": "changed", "of": 7}, {"text": "  ", "kind": "new"}, {"text": "x", "kind": "odd"}]}"#
        let found = FactReader.findings(in: text, known: 2)
        #expect(found == [
            FactReader.Finding(text: "Lorcan has a friend named Noah", kind: .new),
            FactReader.Finding(text: "Lorcan is vegetarian", kind: .same, of: 1),
        ])
        #expect(FactReader.findings(in: #"{"facts": []}"#, known: 0) == [])
        #expect(FactReader.findings(in: "nope", known: 0) == nil)
        #expect(FactReader.findings(in: #"{"fact": "one"}"#, known: 0) == nil, "the old one-sentence shape is not a list")
    }
}
