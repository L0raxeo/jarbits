import Foundation
import Testing
@testable import Answers
@testable import Engine

/// What the prompts say now that only the facts chosen for a query go in:
/// the marker that asks for every fact, the retry that leaves it out, the
/// planner's count of what it was not shown and its `facts` tool.
@Suite struct FactPickPromptTests {
    @Test func anAnswerAsksForEveryFactOnceThenSaysItDoesNotKnow() {
        for format in [Instinct.narrative, .oneLine] {
            let first = AnswerPrompt.system(for: format, persona: .example)
            #expect(first.contains("is answered from that block alone. When it holds something that bears on it, even distantly, answer from that, working out what follows where you must (a junior graduates in two years, in May; the date in the context says which year). Only when nothing in it bears on the subject at all, reply with exactly NEEDS_MY_NOTES and nothing else: the block holds only the facts chosen for this query"), "\(format)")
            #expect(!first.contains("that you don't know that yet"), "\(format): the first asking never says so by itself")
            let retry = AnswerPrompt.system(for: format, persona: .example, retry: true)
            #expect(!retry.contains(AnswerPrompt.notesMarker), "\(format): the retry has every fact; the marker would loop")
            #expect(retry.contains("When it holds nothing on it, say in a line that you don't know that yet;"), "\(format)")
            #expect(retry.contains("never guess, never answer from the world"))
        }
        #expect(AnswerSummary.notesMarkerName == AnswerPrompt.notesMarker, "the report names the marker without importing Answers")
        let request = AnswerPrompt.request(format: .oneLine, query: "q", context: .example, facts: ["f"], persona: .example, retry: true)
        #expect(request.systemInstruction.contains("you don't know that yet"))
        #expect(AnswerPrompt.request(format: .oneLine, query: "q", context: .example, persona: .example).systemInstruction.contains(AnswerPrompt.notesMarker))
    }

    @Test func thePlannerKnowsHowManyFactsItWasNotShownAndHasATool() throws {
        let chosen = Planner.system(facts: ["Lorcan is vegetarian"], held: 212, context: .example, persona: .example)
        #expect(chosen.contains("What Jarbits knows about Lorcan (told earlier; let it shape what you do, never repeat it; the 1 of 212 chosen as bearing on this request, facts finds others):\n- Lorcan is vegetarian"))
        #expect(chosen.contains("call facts with what to look for before saying you don't know"))
        let none = Planner.system(facts: [], held: 40, context: .example, persona: .example)
        #expect(none.contains("- none of the 40 I hold were chosen as bearing on this request; facts looks through them"))
        let every = Planner.system(facts: ["a", "b"], held: 2, context: .example, persona: .example)
        #expect(every.contains("never repeat it):\n- a\n- b"), "every fact shown: no count")
        #expect(Planner.system(facts: ["a"], context: .example).contains("never repeat it):\n- a"), "held left out means every one is shown")
        #expect(Planner.system(facts: [], context: .example).contains("- nothing yet; there is nothing for facts to find"))
        #expect(Planner.system(facts: ["a", "b"], held: 1, context: .example).contains("never repeat it):\n- a"), "a held below the count is the count")
        let tool = try #require(Planner.tools(for: InstinctSpec.all).first { $0.name == "facts" })
        #expect(tool.parameters["required"]?.arrayValue?.first?.stringValue == "about")
        #expect(tool.description.contains("Shows nothing"))
        #expect(Planner.factsResult(["Lorcan's sister Ana is a nurse."], held: 212, about: "the sister") == "found 1 bearing on \"the sister\":\n- Lorcan's sister Ana is a nurse.\n211 more held, not shown")
        #expect(Planner.factsResult([], held: 3, about: "x") == "nothing I hold bears on \"x\" (3 held)")
        #expect(Planner.factsResult(["a"], held: 1, about: "x") == "found 1 bearing on \"x\":\n- a")
        let bundle = PlanBundle(query: "q", exchanges: [], facts: ["f"], factsHeld: 9, tools: [], context: .example, persona: .example)
        let request = Planner.request(bundle: bundle, transcript: [.userText("x")])
        #expect(request.systemInstruction.contains("the 1 of 9 chosen"))
    }

    @Test func thePickAndTheReaderSendTheSameNumberOfExchanges() {
        #expect(FactPicking.exchangesGiven == FactReader.exchangesGiven)
        #expect(Closing.describe(EngineSummary.Step(name: "facts", arguments: ["about": "the sister"], outcome: "read", latencyMs: 3), persona: .example)?.contains("looked through what I know about Lorcan") == true)
    }
}
