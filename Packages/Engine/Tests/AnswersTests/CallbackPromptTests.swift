import Foundation
import Testing
@testable import Answers
@testable import Engine

/// Exchanges from earlier conversations go in a block of their own, under
/// one rule in the Truth block, in an answer's input and the planner's first turn.
@Suite struct CallbackPromptTests {
    private let callback = Callback(id: UUID(), at: Date(timeIntervalSince1970: 1_792_500_000), asked: "is a lobster a bug", said: "Not quite, sir. A crustacean, which is a cousin.")

    @Test func anAnswerGetsTheBlockAfterTheRecordAndTheRuleUnderTruth() throws {
        let input = AnswerPrompt.input(query: "what about crabs", context: .example, done: ["Mon 2 Nov 10:00: Said: Very good, sir."], persona: .example, callbacks: [callback])
        let block = CallbackBook.block([callback], calendar: AnswerPrompt.calendar(.example))
        #expect(input.hasSuffix("- Mon 2 Nov 10:00: Said: Very good, sir.\n\n" + block))
        #expect(block.contains(": you were asked \"is a lobster a bug\" and said \"Not quite, sir. A crustacean, which is a cousin.\""))
        #expect(!AnswerPrompt.input(query: "x", context: .example).contains(CallbackBook.heading), "none, no block")
        let system = AnswerPrompt.system(for: .narrative, persona: .example)
        let truth = try #require(system.range(of: "Truth (never bent):"))
        let character = try #require(system.range(of: "Character (yours"))
        let rule = try #require(system.range(of: CallbackBook.rule))
        #expect(truth.lowerBound < rule.lowerBound && rule.lowerBound < character.lowerBound, "the rule is truth")
        let request = AnswerPrompt.request(format: .oneLine, query: "q", context: .example, persona: .example, callbacks: [callback])
        #expect(request.input.contains(CallbackBook.heading))
    }

    @Test func thePlannerGetsTheBlockInItsFirstTurn() {
        let things = ThingTable(exchanges: [])
        let input = Planner.input(query: "what about crabs", things: things, now: AnswerContext.example.now, calendar: AnswerPrompt.calendar(.example), callbacks: [callback])
        #expect(input.contains(CallbackBook.block([callback], calendar: AnswerPrompt.calendar(.example))))
        #expect(!Planner.input(query: "q", things: things, now: AnswerContext.example.now).contains(CallbackBook.heading))
        #expect(Planner.system(facts: [], context: .example, persona: .example).contains(CallbackBook.rule))
    }
}
