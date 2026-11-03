import Foundation
import Testing
@testable import Answers
@testable import Engine

@Suite struct CheckerTests {
    @Test func theCheckGoesThroughTheDoorWithTheAnswerSoFar() throws {
        let now = AnswerContext.example.now
        let read = ActionRecord(at: now, what: "Read the page \"AlarmKit\" on my screen", kind: .read)
        let done = Done(now: [Done.Entry(record: read, full: "AlarmKit, new in iOS 26, lets an app schedule alarms.")])
        let input = Checker.input(query: "can you set an alarm?", answer: "No, there is no way to", unfinished: true, done: done, persona: .example)
        #expect(input.hasPrefix("Query: can you set an alarm?\n\nYour answer so far, still being written:\nNo, there is no way to\n\nWhat you have done (oldest first):"))
        #expect(input.contains("    AlarmKit, new in iOS 26, lets an app schedule alarms."))
        #expect(Checker.input(query: "q", answer: "a", unfinished: false, done: .none).hasSuffix("Your answer:\na\n\nWhat you have done: nothing."))
        let request = Checker.request(query: "q", answer: "a", unfinished: false, done: .none, persona: .example)
        #expect(request.outputSchema == Checker.schema)
        #expect(request.maxOutputTokens == Checker.maxOutputTokens && request.stream == false)
        #expect(request.systemInstruction.hasPrefix(Persona.example.speakerLine))
        #expect(request.systemInstruction.contains(Done.rule(Done.answerHeading)))
        #expect(request.systemInstruction.contains("Neither is an answer still being written"))
    }

    @Test func aVerdictIsReadOrMissed() {
        #expect(Checker.verdict(in: #"{"contradicts": false, "correction": ""}"#) == .agrees)
        #expect(Checker.verdict(in: #"{"contradicts": true, "correction": "A moment, sir. I was wrong: I did rewrite it."}"#) == .contradicts("A moment, sir. I was wrong: I did rewrite it."))
        #expect(Checker.verdict(in: #"{"contradicts": true, "correction": "  "}"#) == .missed, "a contradiction with nothing to say is no verdict")
        #expect(Checker.verdict(in: "not json") == .missed)
    }
}
