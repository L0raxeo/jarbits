import Foundation
import Testing
@testable import Engine

/// A question about what he did: Jev's reading, the words' reading when
/// Jev did not say, and the note's history answered from the record alone.
@Suite struct DidTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_792_600_000)

    @Test func theDidQuestionRidesOnTheAnswerInstincts() throws {
        let request = EngineRequest.request(for: "did you change this note", locale: Locale(identifier: "en_US"))
        let ids = request.questions.map(\.id)
        #expect(ids.firstIndex(of: "did") == ids.firstIndex(of: "recent").map { $0 + 1 }, "right after recency, asked once")
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let did = try #require((json["questions"] as? [String: Any])?["did"] as? [String: Any])
        #expect(did["type"] as? String == "noul")
        #expect((did["instructions"] as? String)?.contains("the assistant itself did") == true)
    }

    @Test func jevsReadingWinsAndTheWordsStandInWhenItDidNotSay() {
        #expect(Pick(instinct: .narrative, did: 0.9, source: .jev).asksWhatHeDid("tell me about alarms"))
        #expect(!Pick(instinct: .narrative, did: 0.1, source: .jev).asksWhatHeDid("did you change this?"), "Jev said no, and Jev was asked")
        #expect(Pick(instinct: .narrative, source: .plan).asksWhatHeDid("did you change this?"), "no answer: the words decide")
        #expect(Done.asksWhatHeDid("Did you change my note?"))
        #expect(Done.asksWhatHeDid("what did you just do"))
        #expect(Done.asksWhatHeDid("undo that"))
        #expect(!Done.asksWhatHeDid("what is the capital of peru"))
        #expect(!Done.asksWhatHeDid("do you know any vegans"), "\"do you\" is not \"did you\"")
    }

    @Test func theQueryPointsAtTheThingInViewOrNot() {
        #expect(Done.pointsAtThingInView("did you change this?", title: "Trip"))
        #expect(Done.pointsAtThingInView("have you touched my trip note", title: "Trip"))
        #expect(Done.pointsAtThingInView("did you rewrite it", title: "Trip"))
        #expect(!Done.pointsAtThingInView("did you read the alarmkit page", title: "Trip"))
    }

    @Test func aNotesHistoryIsAnsweredFromTheRecordAlone() {
        let id = UUID()
        let shown = ActionRecord(at: now.addingTimeInterval(-3_600), what: "Showed you my note \"Trip\"", noteID: id, kind: .show)
        let changed = ActionRecord(at: now.addingTimeInterval(-600), what: "Rewrote my note \"Trip\": took out 640 of its 760 words and put in 12", noteID: id, kind: .change)
        let said = Done.say(aboutNote: [shown, changed], calendar: calendar, now: now)
        #expect(said == "I did, sir: \(changed.when(calendar: calendar, now: now)) I rewrote my note \"Trip\": took out 640 of its 760 words and put in 12.")
        #expect(said.hasPrefix("I did, sir: at ") && !said.contains(" on "), "today says only the time")
        #expect(Done.say(aboutNote: [changed, shown], calendar: calendar, now: now) == said, "shown after the change: still changed")
        #expect(Done.say(aboutNote: [shown], calendar: calendar, now: now) == "I haven't touched it, sir. I only showed it to you, \(shown.when(calendar: calendar, now: now)).")
        #expect(Done.say(aboutNote: [], calendar: calendar, now: now) == "I haven't touched it, sir.")
        #expect(Done.say(aboutNote: [], address: nil, calendar: calendar, now: now) == "I haven't touched it.")
        let old = ActionRecord(at: now.addingTimeInterval(-3 * 86_400), what: "Made my note \"Trip\"", noteID: id, kind: .change)
        #expect(Done.say(aboutNote: [old], calendar: calendar, now: now).hasPrefix("I did, sir: on "), "another day says the day")
    }
}
