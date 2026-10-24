import Foundation
import Testing
@testable import Routing

/// These share one `URLProtocol` handler, so they run one at a time.
@Suite(.serialized) struct FormatRouterTests {
    @Test func asksJevAndActsOnAConfidentAnswer() async throws {
        let client = MockTransport.client(status: 200, body: jevResponse(choice: "one_line", confidence: 0.88, probabilities: ["one_line": 0.89, "narrative": 0.08, "web_results": 0.03]))
        let router = FormatRouter(client: client, locale: Locale(identifier: "en_US"))

        let decision = await router.decide("what's the time in costa rica")

        #expect(decision.format == .oneLine)
        #expect(decision.source == .jev)
        #expect(decision.latencyMs != nil)

        let sent = try #require(MockTransport.requests.first)
        #expect(sent.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(sent.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((json["state"] as? [String: Any])?["query"] as? String == "what's the time in costa rica")
        #expect((json["questions"] as? [String: Any])?["continues"] == nil, "no answer on screen, no continues question")
    }

    @Test func aRecallPickBringsItsIntentInTheSameRequest() async throws {
        let client = MockTransport.client(status: 200, body: jevResponse(
            choice: "recall", confidence: 0.95, probabilities: ["recall": 0.96, "web_results": 0.04], recency: 0.1,
            nouls: recallNouls(kinds: [.searches, .answers], named: false, all: true)))
        let decision = await FormatRouter(client: client, locale: Locale(identifier: "en_US")).decide("the last 5 things I asked you, including google searches and AI stuff")
        #expect(decision.format == .recall)
        #expect(decision.recall?.wanted == [.searches, .answers])
        #expect(decision.recall?.namesThing == false)
        #expect(MockTransport.requests.count == 1, "the intent rides in the routing request; no second call")
        let body = try #require(MockTransport.requests.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((json["questions"] as? [String: Any])?["recall_named"] != nil)
    }

    @Test func aPreviousTurnReachesJevAndTheAnswerComesBack() async throws {
        let client = MockTransport.client(status: 200, body: jevResponse(
            choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9, "web_results": 0.1], recency: 0.1, continues: 0.85))
        let router = FormatRouter(client: client, locale: Locale(identifier: "en_US"))

        let decision = await router.decide("why?", thread: [
            AnswerTurn(query: "how do you make hot chocolate", answer: "Heat milk, whisk in cocoa."),
            AnswerTurn(query: "why low heat?", answer: "Milk scorches above a simmer."),
        ])

        #expect(decision.continuation == 0.85)
        #expect(decision.continuesThread)
        let body = try #require(MockTransport.requests.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        #expect(state["previous_queries"] as? [String] == ["how do you make hot chocolate", "why low heat?"])
        #expect(state["previous_answer"] as? String == "Milk scorches above a simmer.")
        #expect((json["questions"] as? [String: Any])?["continues"] != nil)
    }

    @Test func addressBypassesJev() async {
        MockTransport.handler = { _ in
            Issue.record("Jev must not be called for an address")
            return (500, Data())
        }
        MockTransport.requests = []
        let router = FormatRouter(client: JevClient(apiKey: "sk-test", session: MockTransport.session()))

        let decision = await router.decide("nasdaq.com")

        #expect(decision == .directURL())
        #expect(MockTransport.requests.isEmpty)
    }

    @Test func httpErrorFallsBackToWeb() async {
        let client = MockTransport.client(status: 401, body: #"{"detail":"invalid api key"}"#)
        let decision = await FormatRouter(client: client).decide("tesla stock")

        #expect(decision.format == .webResults)
        #expect(decision.suggested == nil)
        guard case let .error(message) = decision.source else {
            Issue.record("expected an error source, got \(decision.source)")
            return
        }
        #expect(message.hasPrefix("http 401"))
    }

    @Test func malformedBodyFallsBackToWeb() async {
        let client = MockTransport.client(status: 200, body: "not json")
        let decision = await FormatRouter(client: client).decide("tesla stock")
        #expect(decision.format == .webResults)
        guard case let .error(message) = decision.source else {
            Issue.record("expected an error source")
            return
        }
        #expect(message.hasPrefix("decoding"))
    }

    @Test func aRecallShortlistComesBackJudgedOrFailed() async throws {
        let now = Date(timeIntervalSince1970: 1_792_685_600)
        let video = MemoryRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: now.addingTimeInterval(-86_400), kind: .page, query: "", title: "Rick Steves' Europe: Lisbon", url: URL(string: "https://m.youtube.com/watch?v=a"))
        let recipe = MemoryRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: now.addingTimeInterval(-3_600), kind: .narrative, query: "how do you make hot chocolate", text: "Heat milk.")
        let body = #"{ "model": "jev-1.13.0", "answers": { "m0": { "type": "noul", "noul": 0.95 }, "m1": { "type": "noul", "noul": 0.1 } }, "usage": { "input_tokens": 300, "output_tokens": 4 } }"#
        let client = MockTransport.client(status: 200, body: body)

        let verdict = await RecallResolver(client: client, locale: Locale(identifier: "en_US")).resolve("the video from yesterday", candidates: [video, recipe], now: now)

        guard case let .picked(picks, latencyMs) = verdict else {
            Issue.record("expected picks, got \(verdict)")
            return
        }
        #expect(picks.map(\.record) == [video])
        #expect(latencyMs >= 0)
        let sent = try #require(MockTransport.requests.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect((json["questions"] as? [String: Any])?.count == 2)
        #expect((json["state"] as? [String: Any])?["query"] as? String == "the video from yesterday")

        MockTransport.handler = { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return (200, Data())
        }
        MockTransport.requests = []
        let slow = JevClient(apiKey: "sk-test", timeout: .milliseconds(50), session: MockTransport.session())
        #expect(await RecallResolver(client: slow).resolve("x", candidates: [video], now: now) == .failed("timeout"))
        #expect(await RecallResolver(client: slow).resolve("x", candidates: [], now: now) == .picked([], latencyMs: 0), "nothing to ask about")
    }

    @Test func slowAnswerTimesOut() async {
        MockTransport.handler = { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return (200, Data(jevResponse(choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9]).utf8))
        }
        MockTransport.requests = []
        let client = JevClient(apiKey: "sk-test", timeout: .milliseconds(50), session: MockTransport.session())
        let decision = await FormatRouter(client: client).decide("tesla stock")
        #expect(decision.format == .webResults)
        #expect(decision.source == .error("timeout"))
    }
}
