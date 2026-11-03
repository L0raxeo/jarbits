import Foundation
import Testing
@testable import Answers
@testable import Engine

/// Every model call goes through one door: the same `Done` renders the same
/// lines in every speaker's input, and a reader gets the newest few.
@Suite struct DoneDoorTests {
    private let now = AnswerContext.example.now
    private var done: Done {
        let read = ActionRecord(at: now, what: "Read the page \"AlarmKit\" on my screen, looking for alarms", kind: .read)
        return Done(
            before: [ActionRecord(at: now, what: "Said: Very good, sir.", kind: .say)],
            earlier: 3,
            now: [Done.Entry(record: read, full: "AlarmKit, new in iOS 26, lets an app schedule alarms.")],
            saying: "No, there is no way to"
        )
    }

    @Test func everySpeakerRendersTheSameDoneBlock() throws {
        let calendar = AnswerPrompt.calendar(.example)
        let answer = AnswerPrompt.input(query: "can you set an alarm?", context: .example, done: done)
        let planner = Planner.input(query: "can you set an alarm?", things: ThingTable(), now: now, calendar: calendar, done: done)
        let closing = Closing.input(query: "can you set an alarm?", steps: [], reason: .budget, said: [], done: done)
        // The closing has no context of its own: it renders in the device's calendar.
        for (input, calendar) in [(answer, calendar), (planner, calendar), (closing, .current)] {
            #expect(input.contains("- " + ActionRecord(at: now, what: "Said: Very good, sir.").line(calendar: calendar)))
            #expect(input.contains("For this request, so far:\n- "))
            #expect(input.contains("\n    AlarmKit, new in iOS 26, lets an app schedule alarms."), "what was read, in full")
            #expect(input.contains("Saying now, not finished: No, there is no way to"))
        }
        #expect(answer.contains("What you have done (oldest first):"), "an answer never mentions past")
        #expect(planner.contains("What I have done (oldest first; 3 earlier, which past reads):"))
        #expect(closing.contains("What I have done (oldest first):"))
        let rule = Done.rule(Done.answerHeading)
        #expect(AnswerPrompt.system(for: .narrative, persona: .example).contains(rule))
        #expect(Planner.system(facts: [], context: .example, persona: .example).contains(Done.rule(Done.planHeading)))
        #expect(Closing.system(.example, reason: .budget).contains("A block \"What I have done\" may list what you did and read"))
    }

    @Test func everyReaderGetsTheBriefAndNeverTheWholeText() {
        let factReader = FactReader.input(query: "I'm vegetarian", exchanges: [], known: [], done: done)
        let extractor = ValueExtractor.input(query: "undo that", exchanges: [], done: done)
        let queryReader = QueryReader.request(query: "undo that", done: done).input
        for input in [factReader, extractor, queryReader] {
            #expect(input.contains("What I have just done (oldest first):\n- "))
            #expect(input.contains("- Saying now, not finished: No, there is no way to"))
            #expect(!input.contains("lets an app schedule alarms"), "a reader never gets the whole text")
            #expect(input.hasSuffix("Request: " + (input.contains("vegetarian") ? "I'm vegetarian" : "undo that")))
        }
        #expect(!FactReader.input(query: "hi", exchanges: [], known: [], done: .none).contains("What I have just done"), "none, no block")
    }
}
