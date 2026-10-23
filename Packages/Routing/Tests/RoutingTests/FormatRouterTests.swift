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
        #expect((json["questions"] as? [String: Any])?["continues"] == nil, "no narrative on screen, no continues question")
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
        #expect(decision.continuesNarrative)
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
