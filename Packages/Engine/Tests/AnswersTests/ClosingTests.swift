import Foundation
import Testing
@testable import Answers
@testable import Engine

/// The closing line's request: the instruction, the facts in plain words,
/// what was already said, and how a reply's text becomes the line.
@Suite struct ClosingTests {
    @Test func theInstructionAsksForOnePlainLineFromTheFactsOnly() {
        let system = Closing.system(.example)
        #expect(system.hasPrefix(Persona.example.speakerLine + "\n"))
        #expect(system.contains("From the facts below and nothing else"))
        #expect(system.contains("Never a tool name, a handle, a count of steps or rounds"))
        #expect(system.contains("do not repeat it: add only what is new"))
        #expect(system.contains("never that you did something not listed as tried, and never that you are unable to do a kind of thing"))
        #expect(system.contains("never name another, such as the connection, a timeout or a site being down"), "\"the time ran out\" came back as \"the connection timed out\" (2026-11-01)")
        #expect(system.contains("never promise to look again or to do anything later"), "the plan is over when this line is written")
    }

    @Test func theInputSaysWhatWasTriedInPlainWordsAndWhatWasSaid() {
        let steps = [
            EngineSummary.Step(name: "web_results", arguments: ["query": "campus pizza bethlehem", "screen": "mine"], outcome: "read", latencyMs: 1),
            EngineSummary.Step(name: "look", arguments: ["what": "text"], outcome: "looked: text, 400 chars, 0 links", latencyMs: 1),
            EngineSummary.Step(name: "say", arguments: ["text": "I can't measure distances yet; Maps will tell you which is closer. I'll keep checking."], outcome: "shown", latencyMs: 1),
            EngineSummary.Step(name: "web_results", arguments: ["query": "campus pizza to maginnes hall distance"], outcome: "failed: no reply", latencyMs: 1),
        ]
        let input = Closing.input(query: "which is closer to maginnes hall", steps: steps, reason: .budget, said: Closing.said(in: steps), persona: .example, done: .none)
        #expect(input == """
        Request: which is closer to maginnes hall
        Tried, in order:
        - searched the web for "campus pizza bethlehem" and got something
        - read the page and read it
        - searched the web for "campus pizza to maginnes hall distance" and it did not work
        Why it stopped: I had looked for as long as I allow myself and stopped before settling it
        Already said to Lorcan:
        - I can't measure distances yet; Maps will tell you which is closer. I'll keep checking.
        """, "no handles, no tool names, no counts; the say step is what was said, not a step")
        #expect(Closing.input(query: "q", steps: [], reason: .nothing, said: [], done: .none) == "Request: q\nTried: nothing got started\nWhy it stopped: nothing came of it")
        let request = Closing.request(query: "q", steps: [], reason: .failed, persona: .example, done: .none)
        #expect(request.model == Closing.model && request.maxOutputTokens == Closing.maxOutputTokens && request.stream == false)
    }

    @Test func aReplyBecomesTheLineOrNothing() {
        #expect(Closing.line(in: #"{"line": " I looked for both places but couldn't work out the distance. Maps will know. "}"#) == "I looked for both places but couldn't work out the distance. Maps will know.")
        #expect(Closing.line(in: #"{"line": ""}"#) == nil)
        #expect(Closing.line(in: "not json") == nil)
    }

    @Test func aPlanThatPartlyWorkedIsReadThingByThing() {
        let system = Closing.system(.example, reason: .partly)
        #expect(system.hasPrefix(Persona.example.speakerLine + "\n"))
        #expect(system.contains("if any step got the thing, got is true"), "a recall that failed before a search found it came back as a shortfall (2026-11-02)")
        #expect(system.contains("never of what got done"))
        #expect(system.contains("never promise to look again or to do anything later"))
        #expect(!Closing.system(.example).contains("If nothing is left"), "a plan that could not finish always gets its line")
        let request = Closing.request(query: "q", steps: [], reason: .partly, persona: .example, done: .none)
        #expect(request.systemInstruction == system && request.outputSchema == Closing.partlySchema)
        #expect(request.maxOutputTokens == Closing.partlyMaxOutputTokens, "120 cut the reply off before its closing brace (2026-11-02)")
        #expect(Closing.request(query: "q", steps: [], reason: .failed, persona: .example, done: .none).outputSchema == Closing.schema)
    }

    @Test func theLineStandsOnlyWhenAThingIsLeft() {
        let left = #"{"things": [{"thing": "milk", "got": true, "already_said": false}, {"thing": "text Noah", "got": false, "already_said": false}], "line": " I couldn't send that text, sir. "}"#
        #expect(Closing.remainder(in: left) == .line("I couldn't send that text, sir."))
        #expect(Closing.remainder(in: #"{"things": [{"thing": "the article", "got": true, "already_said": false}], "line": "I've brought it up, sir."}"#) == .nothing, "all of it happened: whatever the line says goes unsaid")
        #expect(Closing.remainder(in: #"{"things": [{"thing": "call", "got": false, "already_said": true}], "line": "I can't call."}"#) == .nothing, "said already")
        #expect(Closing.remainder(in: #"{"things": [{"thing": "call", "got": false, "already_said": false}], "line": ""}"#) == .missed)
        #expect(Closing.remainder(in: "not json") == .missed)
        #expect(Closing.remainder(in: #"{"line": "no reading"}"#) == .missed)
    }

    @Test func aFailedAnswerIsTheOneStepTried() {
        let steps = Closing.failedAnswer(query: "who wrote it", format: .narrative)
        #expect(Closing.input(query: "who wrote it", steps: steps, reason: .failed, said: [], done: .none) == """
        Request: who wrote it
        Tried, in order:
        - tried to answer "who wrote it" and it did not work
        Why it stopped: every step failed
        """)
        #expect(Closing.failedAnswer(query: "q", format: .oneLine).first?.name == "one_line")
    }
}
