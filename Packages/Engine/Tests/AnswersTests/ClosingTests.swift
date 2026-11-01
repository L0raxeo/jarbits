import Foundation
import Testing
@testable import Answers
@testable import Engine

/// The closing line's request: the instruction, the facts in plain words,
/// what was already said, and how a reply's text becomes the line.
@Suite struct ClosingTests {
    @Test func theInstructionAsksForOnePlainLineFromTheFactsOnly() {
        let system = Closing.system(.example)
        #expect(system.hasPrefix(Persona.example.identityLine + "\n"))
        #expect(system.contains("From the facts below and nothing else"))
        #expect(system.contains("Never a tool name, a handle, a count of steps or rounds"))
        #expect(system.contains("do not repeat it: add only what is new"))
    }

    @Test func theInputSaysWhatWasTriedInPlainWordsAndWhatWasSaid() {
        let steps = [
            EngineSummary.Step(name: "web_results", arguments: ["query": "campus pizza bethlehem", "screen": "mine"], outcome: "read", latencyMs: 1),
            EngineSummary.Step(name: "look", arguments: ["what": "text"], outcome: "looked: text, 400 chars, 0 links", latencyMs: 1),
            EngineSummary.Step(name: "say", arguments: ["text": "I can't measure distances yet; Maps will tell you which is closer. I'll keep checking."], outcome: "shown", latencyMs: 1),
            EngineSummary.Step(name: "web_results", arguments: ["query": "campus pizza to maginnes hall distance"], outcome: "failed: no reply", latencyMs: 1),
        ]
        let input = Closing.input(query: "which is closer to maginnes hall", steps: steps, reason: .budget, said: Closing.said(in: steps), persona: .example)
        #expect(input == """
        Request: which is closer to maginnes hall
        Tried, in order:
        - searched the web for "campus pizza bethlehem" and got something
        - read the page and read it
        - searched the web for "campus pizza to maginnes hall distance" and it did not work
        Why it stopped: the time ran out
        Already said to Lorcan:
        - I can't measure distances yet; Maps will tell you which is closer. I'll keep checking.
        """, "no handles, no tool names, no counts; the say step is what was said, not a step")
        #expect(Closing.input(query: "q", steps: [], reason: .nothing, said: []) == "Request: q\nTried: nothing got started\nWhy it stopped: nothing came of it")
        let request = Closing.request(query: "q", steps: [], reason: .failed, persona: .example)
        #expect(request.model == Closing.model && request.maxOutputTokens == Closing.maxOutputTokens && request.stream == false)
    }

    @Test func aReplyBecomesTheLineOrNothing() {
        #expect(Closing.line(in: #"{"line": " I looked for both places but couldn't work out the distance. Maps will know. "}"#) == "I looked for both places but couldn't work out the distance. Maps will know.")
        #expect(Closing.line(in: #"{"line": ""}"#) == nil)
        #expect(Closing.line(in: "not json") == nil)
    }
}
