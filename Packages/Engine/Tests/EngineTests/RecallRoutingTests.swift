import Foundation
import Testing
@testable import Engine

/// Pure: the request shape and the reading of the answers. The resolver's
/// network test lives in `FormatRouterTests`, which owns the one mock transport.
@Suite struct RecallRoutingTests {
    private let now = Date(timeIntervalSince1970: 1_792_685_600)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }
    private var video: Webpage {
        Webpage(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, kind: .page, address: URL(string: "https://m.youtube.com/watch?v=a")!, title: "Rick Steves' Europe: Lisbon", opened: now.addingTimeInterval(-86_400))
    }
    private var recipe: Webpage {
        Webpage(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, kind: .search, address: QueryParser.searchURL(for: "how do you make hot chocolate"), query: "how do you make hot chocolate", opened: now.addingTimeInterval(-3_600))
    }

    private func answers(_ values: [String: Double]) -> String {
        let pairs = values.map { "\"\($0.key)\": { \"type\": \"noul\", \"noul\": \($0.value) }" }.joined(separator: ", ")
        return "{ \"model\": \"jev-1.13.0\", \"answers\": { \(pairs) }, \"usage\": { \"input_tokens\": 300, \"output_tokens\": 4 } }"
    }

    @Test func aCollectionAsksWhetherEachWebpageIsAboutTheTopic() throws {
        let request = RecallRouting.request(for: "everything about lisbon", candidates: [video, recipe], now: now, locale: Locale(identifier: "en_US"), calendar: calendar, collection: true)
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let questions = try #require(json["questions"] as? [String: Any])
        let first = try #require(questions["m0"] as? [String: Any])
        let text = try #require(first["instructions"] as? String)
        #expect(text.hasPrefix("Is this webpage about what the query asks for everything about? A web page open since yesterday (m.youtube.com)"), "got: \(text)")
        #expect((first["criteria"] as? [String: String])?["true"] == RecallRouting.collectionCriteria.yes)
        let plain = RecallRouting.request(for: "the video from yesterday", candidates: [video], now: now, locale: Locale(identifier: "en_US"), calendar: calendar)
        let plainText = try #require(((try JSONSerialization.jsonObject(with: try plain.jsonData()) as? [String: Any])?["questions"] as? [String: Any])?["m0"] as? [String: Any])["instructions"] as? String
        #expect(plainText?.hasPrefix("Is this the webpage the query asks for?") == true)
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
        #expect(text.contains("web page open since yesterday (m.youtube.com): \"Rick Steves' Europe: Lisbon\""), "got: \(text)")
        let second = try #require((questions["m1"] as? [String: Any])?["instructions"] as? String)
        #expect(second == "Is this the webpage the query asks for? A search open since today: \"how do you make hot chocolate\".", "a search has no host and no excerpt; got: \(second)")
        #expect(Set((first["criteria"] as? [String: String])?.keys.map { $0 } ?? []) == ["true", "false"])
    }

    @Test func whenIsRelativeThenDated() {
        #expect(RecallRouting.when(now.addingTimeInterval(-600), now: now, calendar: calendar) == "today")
        #expect(RecallRouting.when(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "yesterday")
        #expect(RecallRouting.when(now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar) == "3 days ago")
        #expect(RecallRouting.when(now.addingTimeInterval(-10 * 86_400), now: now, calendar: calendar) == "on Oct 12")
    }

    @Test func picksAreTheYesesSurestFirst() throws {
        let candidates = [video, recipe, Webpage(kind: .search, address: QueryParser.searchURL(for: "can you use water?"), query: "can you use water?")]
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(answers(["m0": 0.2, "m1": 0.9, "m2": RecallRouting.maybeThreshold]).utf8))
        let picks = RecallRouting.picks(from: response, candidates: candidates)
        #expect(picks.map(\.webpage.query) == ["how do you make hot chocolate", "can you use water?"], "surest first; the plausible bar is inclusive")
        #expect(picks.map(\.probability) == [0.9, RecallRouting.maybeThreshold])
        let missing = try JSONDecoder().decode(SystemOneResponse.self, from: Data(answers(["m0": 0.9]).utf8))
        #expect(RecallRouting.picks(from: missing, candidates: candidates).map(\.webpage) == [video], "a missing answer is a no")
    }
}
