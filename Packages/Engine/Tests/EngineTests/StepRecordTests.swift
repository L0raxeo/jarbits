import Foundation
import Testing
@testable import Engine

@Suite struct StepRecordTests {
    @Test func everyOutcomeKindHasOneRecordingDecision() {
        func line(_ outcome: String, name: String = "notebook", recordedAlready: Bool = false, isAnswer: Bool = false, isInstinct: Bool = true) -> StepRecord.Line? {
            StepRecord.line(name: name, outcome: outcome, result: "the result", recordedAlready: recordedAlready, isAnswer: isAnswer, isInstinct: isInstinct)
        }
        #expect(line("ran") == StepRecord.Line(what: "notebook: the result", kind: .change))
        #expect(line("shown", name: "map") == StepRecord.Line(what: "map: the result", kind: .show))
        #expect(line("failed: nothing opened") == StepRecord.Line(what: "Tried notebook and could not: the result", kind: .tried))
        #expect(line("failed: empty", name: "say", isInstinct: false) == nil, "a planner tool's failure is not his")
        #expect(line("failed: no such thing") == nil, "a handle that is not there tried nothing")
        for silent in ["read", "found nothing", "found 3", "looked: text, 400 chars, 2 links", "looked: no reply", "asked", "dismissed", "done", "declined", "already ran", "unknown", "skipped: budget"] {
            #expect(line(silent) == nil, Comment(rawValue: silent))
        }
        #expect(line("something new") != nil, "an outcome no one named is recorded, not lost")
    }

    @Test func aStepNeverRecordsTwice() {
        #expect(StepRecord.line(name: "remember", outcome: "ran", result: "kept", recordedAlready: true, isAnswer: false, isInstinct: true) == nil, "the store wrote its line")
        #expect(StepRecord.line(name: "narrative", outcome: "shown", result: "shown on screen", recordedAlready: false, isAnswer: true, isInstinct: true) == nil, "an answer is recorded when its words are out")
        #expect(StepRecord.line(name: "trigger", outcome: "failed: no time", result: "could not", recordedAlready: true, isAnswer: false, isInstinct: true) != nil, "a failure is his whatever else was written")
    }
}
