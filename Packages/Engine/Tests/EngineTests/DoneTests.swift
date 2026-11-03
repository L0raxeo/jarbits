import Foundation
import Testing
@testable import Engine

@Suite struct DoneTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }
    private let at = Date(timeIntervalSince1970: 1_792_600_000)

    @Test func nothingDoneIsNoBlock() {
        #expect(Done.none.block(heading: Done.answerHeading) == nil)
        #expect(Done.none.brief() == nil)
        #expect(Done.none.isEmpty)
    }

    @Test func theBlockIsBytesForBytesWhatTheListingHadWhenNothingHappenedYet() {
        let id = UUID()
        let record = ActionRecord(at: at, what: "Rewrote my note \"Trip\"", noteID: id, asked: "tidy this")
        let done = Done(before: [record], earlier: 40)
        let planner = done.block(heading: Done.planHeading, calendar: calendar, noteHandles: [id: "n1"], past: true)
        #expect(planner == "What I have done (oldest first; 40 earlier, which past reads):\n- " + record.line(calendar: calendar, noteHandles: [id: "n1"]))
        let answer = done.block(heading: Done.answerHeading, calendar: calendar)
        #expect(answer == "What you have done (oldest first):\n- " + record.line(calendar: calendar), "an answer never mentions past")
    }

    @Test func aReadThisRequestIsRenderedInFullUnderTheOlderLines() throws {
        let older = ActionRecord(at: at, what: "Said: Done, sir.")
        let read = ActionRecord(at: at, what: "Read the page \"AlarmKit\" on my screen, looking for whether alarms can be set: AlarmKit, new in iOS 26…", kind: .read)
        let done = Done(before: [older], now: [Done.Entry(record: read, full: "AlarmKit, new in iOS 26, lets an app schedule alarms.\nThey ring even in silent mode.")])
        let block = try #require(done.block(heading: Done.planHeading, calendar: calendar))
        let lines = block.split(separator: "\n").map(String.init)
        #expect(lines[1].hasSuffix(": Said: Done, sir."))
        #expect(lines[2] == "For this request, so far:")
        #expect(lines[3].contains("Read the page \"AlarmKit\""))
        #expect(lines[4] == "    AlarmKit, new in iOS 26, lets an app schedule alarms.")
        #expect(lines[5] == "    They ring even in silent mode.")
        let long = Done(now: [Done.Entry(record: read, full: String(repeating: "x", count: Done.maxFull + 10))])
        #expect(try #require(long.block(heading: Done.planHeading)).hasSuffix("…"), "a long read is cut")
        let same = Done(now: [Done.Entry(record: older, full: older.what)])
        #expect(try #require(same.block(heading: Done.planHeading)).split(separator: "\n").count == 3, "a full that is the line itself is not repeated")
    }

    @Test func whatHeIsSayingNowIsTheLastLine() throws {
        let done = Done(before: [ActionRecord(at: at, what: "Said: one")], saying: "No, there is no way to")
        let block = try #require(done.block(heading: Done.answerHeading, calendar: calendar))
        #expect(block.hasSuffix("\nSaying now, not finished: No, there is no way to"))
        #expect(Done(saying: "   ").block(heading: Done.answerHeading) == "What you have done (oldest first):", "blank words are not a line")
    }

    @Test func theBriefIsTheNewestFewForAReader() throws {
        let before = (1...5).map { ActionRecord(at: at, what: "thing \($0)") }
        let now = [Done.Entry(record: ActionRecord(at: at, what: "thing 6", kind: .read), full: "a whole page of text")]
        let brief = try #require(Done(before: before, now: now, saying: "and").brief(calendar: calendar))
        let lines = brief.split(separator: "\n").map(String.init)
        #expect(lines[0] == "What I have just done (oldest first):")
        #expect(lines.count == Done.briefCount + 2)
        #expect(lines[1].hasSuffix(": thing 3") && lines[4].hasSuffix(": thing 6"))
        #expect(!brief.contains("a whole page"), "never the whole text")
        #expect(lines[5] == "- Saying now, not finished: and")
    }

    @Test func anOldRecordWithoutAKindStillDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(ActionRecord.self, from: Data(#"{"at":"2026-10-30T14:00:00Z","what":"Said: hello"}"#.utf8))
        #expect(old.kind == nil && old.what == "Said: hello")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let kept = try decoder.decode(ActionRecord.self, from: try encoder.encode(ActionRecord(at: at, what: "Read it", kind: .read)))
        #expect(kept.kind == .read)
    }

    @Test func theRecordSaysWhereARequestBeganAndWhatCameAfter() {
        let url = FileManager.default.temporaryDirectory.appending(path: "actions-\(UUID().uuidString).jsonl")
        let log = ActionLog(fileURL: url)
        for number in 1...3 { log.add("thing \(number)") }
        let from = log.count
        let place = log.add("Read it", kind: .read)
        #expect(place == 3)
        log.add("Said: done", kind: .say)
        #expect(log.since(from).map(\.what) == ["Read it", "Said: done"])
        #expect(log.since(9).isEmpty)
        let found = log.newest(2, before: from)
        #expect(found.records.map(\.what) == ["thing 2", "thing 3"] && found.earlier == 1)
        #expect(log.newest(before: 0).records.isEmpty)
    }
}
