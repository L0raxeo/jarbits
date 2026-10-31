import Foundation
import Testing
@testable import Engine

/// The memory record on disk: the flat shape from before parts reads as
/// parts, the current shape round-trips, and the head decides the kind.
@Suite struct MemoryShapeTests {
    private func decode(_ json: String) throws -> MemoryRecord {
        try DecisionRecord.decoder.decode(MemoryRecord.self, from: Data(json.utf8))
    }

    private func roundTrip(_ record: MemoryRecord) throws -> MemoryRecord {
        try DecisionRecord.decoder.decode(MemoryRecord.self, from: DecisionRecord.encoder.encode(record))
    }

    @Test func aFlatPageLineBecomesAPagePart() throws {
        let record = try decode(#"{"kind":"page","url":"https:\/\/www.hennesseyperformance.com\/","query":"","title":"Hennessey Performance | Official Website","id":"E096B144-75FD-4698-9849-9AAA7F9DD087","date":"2026-10-23T04:52:23Z"}"#)
        #expect(record.kind == .page)
        #expect(record.url?.host() == "www.hennesseyperformance.com")
        #expect(record.title == "Hennessey Performance | Official Website")
        #expect(record.parts.count == 1)
        #expect(record.cameFrom == nil && record.kept == nil)
        #expect(record.version == MemoryRecord.currentVersion)
        #expect(record.text == nil && record.turns == nil)
    }

    @Test func flatAnswerLinesBecomeAnswerParts() throws {
        let narrative = try decode(#"{"kind":"narrative","query":"how is gingivitis healed","title":"how is gingivitis healed","text":"Remove the ==plaque==.","id":"11111111-1111-1111-1111-111111111111","date":"2026-10-20T10:00:00Z"}"#)
        #expect(narrative.kind == .narrative)
        #expect(narrative.text == "Remove the ==plaque==.")
        #expect(narrative.turns == nil)
        #expect(narrative.exchanges == [AnswerTurn(query: "how is gingivitis healed", answer: "Remove the ==plaque==.", format: .narrative)])

        let oneLine = try decode(#"{"kind":"one_line","query":"capital of peru","title":"capital of peru","id":"22222222-2222-2222-2222-222222222222","date":"2026-10-20T10:00:00Z"}"#)
        #expect(oneLine.kind == .oneLine)
        #expect(oneLine.text == nil, "a bare one-line answer kept no text")

        let conversation = try decode(#"{"kind":"narrative","query":"how do you make hot chocolate","title":"how do you make hot chocolate","text":"Heat milk.","turns":[{"query":"how do you make hot chocolate","answer":"Heat milk.","format":"narrative"},{"query":"and with oat milk?","answer":"Keep it under a simmer.","format":"narrative"}],"id":"33333333-3333-3333-3333-333333333333","date":"2026-10-20T10:00:00Z"}"#)
        #expect(conversation.parts.count == 2)
        #expect(conversation.turns?.count == 2)
        #expect(conversation.turns?.last?.answer == "Keep it under a simmer.")
        #expect(conversation.text == "Heat milk.")
        #expect(conversation.kind == .narrative)
    }

    @Test func flatPictureAndSearchLines() throws {
        let picture = try decode(#"{"kind":"image","query":"eiffel tower","title":"eiffel tower","id":"44444444-4444-4444-4444-444444444444","date":"2026-10-20T10:00:00Z"}"#)
        #expect(picture.kind == .image)
        let search = try decode(#"{"kind":"search","query":"dyson pencilvac","title":"dyson pencilvac","id":"55555555-5555-5555-5555-555555555555","date":"2026-10-20T10:00:00Z"}"#)
        #expect(search.kind == .search)
        #expect(search.title == "dyson pencilvac")
    }

    @Test func theCurrentShapeRoundTrips() throws {
        let from = UUID()
        let record = MemoryRecord(
            date: Date(timeIntervalSince1970: 1_792_700_000),   // whole seconds: the file keeps none finer
            title: "Dyson PencilVac | Dyson", query: "dyson pencilvac",
            parts: [MemoryPart(.page(address: URL(string: "https://www.dyson.com/pencilvac")!, title: "Dyson PencilVac | Dyson")), MemoryPart(.note(text: "the one mom wanted"))],
            cameFrom: from, kept: Date(timeIntervalSince1970: 1_792_600_000)
        )
        let back = try roundTrip(record)
        #expect(back == record)
        #expect(back.cameFrom == from)
        #expect(back.kept != nil)
        let json = String(decoding: try DecisionRecord.encoder.encode(record), as: UTF8.self)
        #expect(json.contains("\"parts\""))
        #expect(!json.contains("\"kind\""), "the flat keys are read, never written")
        #expect(!json.contains("\"own\""), "a page the user saw carries no mark")
        var read = record
        read.own = true
        let readBack = try roundTrip(read)
        #expect(readBack.own == true)
        #expect(String(decoding: try DecisionRecord.encoder.encode(read), as: UTF8.self).contains("\"own\":true"))
    }

    @Test func anUnknownPartIsDroppedAndTheRecordSurvives() throws {
        let record = try decode(#"{"id":"66666666-6666-6666-6666-666666666666","date":"2026-10-20T10:00:00Z","title":"t","query":"q","version":2,"parts":[{"id":"77777777-7777-7777-7777-777777777777","content":{"search":{"query":"q"}}},{"id":"88888888-8888-8888-8888-888888888888","content":{"hologram":{"depth":3}}}]}"#)
        #expect(record.parts.count == 1)
        #expect(record.kind == .search)
        #expect(throws: (any Error).self) {
            try decode(#"{"id":"99999999-9999-9999-9999-999999999999","date":"2026-10-20T10:00:00Z","title":"t","query":"q","version":2,"parts":[{"id":"77777777-7777-7777-7777-777777777777","content":{"hologram":{}}}]}"#)
        }
    }

    @Test func twoBuildsOfTheSameFlatRecordAreEqual() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_792_700_000)
        let a = MemoryRecord(id: id, date: date, kind: .page, query: "", title: "Lisbon", url: URL(string: "https://m.youtube.com/watch?v=a"))
        let b = MemoryRecord(id: id, date: date, kind: .page, query: "", title: "Lisbon", url: URL(string: "https://m.youtube.com/watch?v=a"))
        #expect(a == b)
        let fixture = MemoryRecord(kind: .page, query: "reddit")
        #expect(fixture.kind == .page && fixture.url == nil, "a page fixture without an address is still a page")
    }

    @Test func theFactoryBuildsPartsFromTheFlatFields() {
        let conversation = MemoryRecord(kind: .oneLine, query: "capital of peru", text: "==Lima==", turns: [
            AnswerTurn(query: "capital of peru", answer: "==Lima==", format: .oneLine),
            AnswerTurn(query: "and bolivia?", answer: "==Sucre==", format: .oneLine),
        ])
        #expect(conversation.parts.count == 2)
        #expect(conversation.kind == .oneLine)
        #expect(conversation.turns?.count == 2)
        let page = MemoryRecord(kind: .page, query: "rick steves", title: "Rick Steves' Europe", url: URL(string: "https://m.youtube.com/watch?v=a"))
        #expect(page.title == "Rick Steves' Europe")
        if case let .page(_, title) = page.head.content { #expect(title == "Rick Steves' Europe") } else { Issue.record("the head is not a page") }
        let untitled = MemoryRecord(title: nil, query: "capital of peru", parts: [MemoryPart(.answer(question: "capital of peru", text: "Lima", format: .oneLine))])
        #expect(untitled.title == "capital of peru", "an answer has no title of its own; the query stands in")
    }

    @Test func shortTermExpiresAfterAWeekKeptNever() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        let day: TimeInterval = 86_400
        let fresh = MemoryRecord(date: now.addingTimeInterval(-6 * day), kind: .search, query: "a")
        let stale = MemoryRecord(date: now.addingTimeInterval(-8 * day), kind: .search, query: "b")
        let kept = MemoryRecord(date: now.addingTimeInterval(-80 * day), kind: .search, query: "c", kept: now.addingTimeInterval(-79 * day))
        #expect(!fresh.expires(by: now))
        #expect(stale.expires(by: now))
        #expect(!kept.expires(by: now))
    }

    @Test func sameThingReadsTheHead() {
        let a = MemoryRecord(kind: .page, query: "x", url: URL(string: "https://example.com/a"))
        let b = MemoryRecord(title: "other title", query: "", parts: [MemoryPart(.page(address: URL(string: "https://example.com/a")!, title: "other title")), MemoryPart(.note(text: "n"))])
        #expect(a.sameThing(as: b), "a page is the same page whatever is attached to it")
        #expect(!MemoryRecord(kind: .search, query: "dyson").sameThing(as: MemoryRecord(kind: .narrative, query: "dyson")))
    }

    @Test func anActionPartIsWhatAPlanDid() throws {
        let record = MemoryRecord(date: Date(timeIntervalSince1970: 1_792_700_000), query: "remember I'm vegetarian, then suggest dinner", parts: [
            MemoryPart(.action(name: "remember", arguments: ["query": "I'm vegetarian", "fact": "I'm vegetarian"], result: "kept: I'm vegetarian")),
        ])
        #expect(record.kind == .action)
        #expect(record.kind.label == "action" && record.kind.symbol == "bolt")
        #expect(record.title == "kept: I'm vegetarian", "the result is its title")
        #expect(record.text == "kept: I'm vegetarian")
        #expect(record.url == nil && record.turns == nil)
        let back = try roundTrip(record)
        #expect(back == record)
        #expect(back.parts[0].content == .action(name: "remember", arguments: ["query": "I'm vegetarian", "fact": "I'm vegetarian"], result: "kept: I'm vegetarian"))
        #expect(MemorySearch.matches([record], topic: "vegetarian") == [record], "found by its result")
        let factory = MemoryRecord(kind: .action, query: "q", title: "forget", text: "dropped: I'm vegetarian")
        #expect(factory.kind == .action && factory.text == "dropped: I'm vegetarian")
        #expect(MemoryRecord(kind: .action, query: "q", title: "remember").title == "remember", "a bare action is titled by its name")
    }

    @Test func theHaystackCoversEveryPart() {
        let record = MemoryRecord(title: "Dyson PencilVac | Dyson", query: "", parts: [
            MemoryPart(.page(address: URL(string: "https://www.dyson.com/pencilvac")!, title: "Dyson PencilVac | Dyson")),
            MemoryPart(.note(text: "the best cooking show ever")),
        ])
        #expect(MemorySearch.matches([record], topic: "cooking show") == [record])
    }
}
