import Foundation
import Testing
@testable import Routing

/// Pure: the request shape and the reading of the answers. The resolver's
/// network test lives in `FormatRouterTests`, which owns the one mock transport.
@Suite struct RecallRoutingTests {
    private let now = Date(timeIntervalSince1970: 1_792_685_600)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }
    private var video: MemoryRecord {
        MemoryRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: now.addingTimeInterval(-86_400), kind: .page, query: "", title: "Rick Steves' Europe: Lisbon", url: URL(string: "https://m.youtube.com/watch?v=a"))
    }
    private var recipe: MemoryRecord {
        MemoryRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: now.addingTimeInterval(-3_600), kind: .narrative, query: "how do you make hot chocolate", text: "You **heat milk** and whisk in ==cocoa==.")
    }

    private func answers(_ values: [String: Double]) -> String {
        let pairs = values.map { "\"\($0.key)\": { \"type\": \"noul\", \"noul\": \($0.value) }" }.joined(separator: ", ")
        return "{ \"model\": \"jev-1.13.0\", \"answers\": { \(pairs) }, \"usage\": { \"input_tokens\": 300, \"output_tokens\": 4 } }"
    }

    @Test func oneYesNoQuestionPerCandidate() throws {
        let request = RecallRouting.request(for: "the video from yesterday", candidates: [video, recipe], now: now, locale: Locale(identifier: "en_US"), calendar: calendar)
        #expect(request.questions.map(\.id) == ["m0", "m1"])
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        #expect((json["state"] as? [String: Any])?["query"] as? String == "the video from yesterday")
        let questions = try #require(json["questions"] as? [String: Any])
        let first = try #require(questions["m0"] as? [String: Any])
        #expect(first["type"] as? String == "noul")
        let text = try #require(first["instructions"] as? String)
        #expect(text.contains("web page from yesterday (m.youtube.com): \"Rick Steves' Europe: Lisbon\""), "got: \(text)")
        let second = try #require((questions["m1"] as? [String: Any])?["instructions"] as? String)
        #expect(second.contains("written answer from today"), "got: \(second)")
        #expect(second.contains("It begins: \"You heat milk and whisk in cocoa.\""), "markup stripped")
        #expect(Set((first["criteria"] as? [String: String])?.keys.map { $0 } ?? []) == ["true", "false"])
    }

    @Test func whenIsRelativeThenDated() {
        #expect(RecallRouting.when(now.addingTimeInterval(-600), now: now, calendar: calendar) == "today")
        #expect(RecallRouting.when(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "yesterday")
        #expect(RecallRouting.when(now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar) == "3 days ago")
        #expect(RecallRouting.when(now.addingTimeInterval(-10 * 86_400), now: now, calendar: calendar) == "on Oct 12")
    }

    @Test func picksAreTheYesesSurestFirst() throws {
        let candidates = [video, recipe, MemoryRecord(kind: .search, query: "can you use water?")]
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(answers(["m0": 0.2, "m1": 0.9, "m2": RecallRouting.maybeThreshold]).utf8))
        let picks = RecallRouting.picks(from: response, candidates: candidates)
        #expect(picks.map(\.record.kind) == [.narrative, .search], "surest first; the plausible bar is inclusive")
        #expect(picks.map(\.probability) == [0.9, RecallRouting.maybeThreshold])
        let missing = try JSONDecoder().decode(SystemOneResponse.self, from: Data(answers(["m0": 0.9]).utf8))
        #expect(RecallRouting.picks(from: missing, candidates: candidates).map(\.record) == [video], "a missing answer is a no")
    }
}
