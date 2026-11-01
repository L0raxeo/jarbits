import Foundation
import Engine
import Testing
@testable import Answers

@Suite struct SSEParserTests {
    @Test func splitsFieldsAndEndsOnBlankLine() {
        var parser = SSEParser()
        #expect(parser.feed(line: ": comment") == nil)
        #expect(parser.feed(line: "event: step.delta") == nil)
        #expect(parser.feed(line: "data: {\"a\":1}") == nil)
        #expect(parser.feed(line: "data: {\"b\":2}") == nil)
        #expect(parser.feed(line: "") == SSEParser.Event(name: "step.delta", data: "{\"a\":1}\n{\"b\":2}"))
        #expect(parser.feed(line: "") == nil, "a second blank line is not an event")
        #expect(parser.feed(line: "data:[DONE]") == nil)
        #expect(parser.flush() == SSEParser.Event(name: "", data: "[DONE]"))
    }
}

@Suite struct InteractionStreamTests {
    private func events(_ name: String, _ data: String) throws -> [AnswerEvent] {
        try InteractionStream.events(SSEParser.Event(name: name, data: data))
    }

    @Test func textComesOnlyFromDeltas() throws {
        #expect(try events("step.delta", #"{"delta":{"type":"text","text":"Hi"}}"#) == [.text("Hi")])
        #expect(try events("step.delta", #"{"delta":{"type":"thought","text":"hmm"}}"#) == [])
        #expect(try events("step.start", #"{"step":{"type":"model_output","content":[{"type":"text","text":"Hi"}]}}"#) == [])
        #expect(try events("step.stop", #"{"step":{"type":"model_output","content":[{"type":"text","text":"Hi"}]}}"#) == [])
    }

    @Test func completionCarriesUsageAndStatus() throws {
        let data = #"{"interaction":{"status":"completed","usage":{"total_input_tokens":10,"total_output_tokens":2,"total_thought_tokens":0}}}"#
        #expect(try events("interaction.completed", data) == [
            .usage(AnswerUsage(inputTokens: 10, outputTokens: 2, thoughtTokens: 0)),
            .finished(status: "completed"),
        ])
    }

    @Test func unknownFramesAreIgnoredAndErrorsThrow() throws {
        #expect(try events("interaction.created", #"{"interaction":{"id":"x"}}"#) == [])
        #expect(try events("done", "[DONE]") == [])
        #expect(throws: GeminiError.stream("quota exceeded")) {
            try events("error", #"{"error":{"code":429,"message":"quota exceeded"}}"#)
        }
        #expect(throws: GeminiError.self) { try events("step.delta", "not json") }
    }
}

/// These share one `URLProtocol` handler, so they run one at a time.
@Suite(.serialized) struct GeminiClientTests {
    private func collect(_ client: GeminiClient, _ request: InteractionRequest) async -> (events: [AnswerEvent], error: GeminiError?) {
        var events: [AnswerEvent] = []
        do {
            for try await event in client.stream(request) { events.append(event) }
            return (events, nil)
        } catch {
            return (events, error as? GeminiError)
        }
    }

    private let request = AnswerPrompt.request(format: .oneLine, query: "what's the time in costa rica", context: .example)

    @Test func streamsAnAnswerInOrder() async throws {
        let client = MockGeminiTransport.client(status: 200, body: answerStream)
        let (events, error) = await collect(client, request)
        #expect(error == nil)
        #expect(events == [
            .text("8:14 "),
            .text("PM"),
            .usage(AnswerUsage(inputTokens: 412, outputTokens: 6, thoughtTokens: 3)),
            .finished(status: "completed"),
        ])

        let sent = try #require(MockGeminiTransport.requests.first)
        #expect(sent.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(sent.httpBody == (try request.jsonData()))
    }

    @Test func httpErrorsSurfaceStatusAndBody() async {
        let (events, error) = await collect(MockGeminiTransport.client(status: 401, body: #"{"error":{"message":"API key not valid"}}"#), request)
        #expect(events.isEmpty)
        #expect(error == .http(status: 401, body: #"{"error":{"message":"API key not valid"}}"#))
    }

    @Test func errorFrameAfterTextKeepsTheText() async {
        let body = """
        event: step.delta
        data: {"delta":{"type":"text","text":"Lim"}}

        event: error
        data: {"error":{"code":500,"message":"backend"}}

        """
        let (events, error) = await collect(MockGeminiTransport.client(status: 200, body: body), request)
        #expect(events == [.text("Lim")])
        #expect(error == .stream("backend"))
    }

    @Test func sendReturnsTheWholeBodyWithStreamOff() async throws {
        let client = MockGeminiTransport.client(status: 200, body: InteractionResponseTests.planBody)
        var streamed = request
        streamed.stream = true   // forced off by send
        let data = try await client.send(streamed)
        #expect(data == Data(InteractionResponseTests.planBody.utf8))
        // A slow test's request can land in the list late; this one is the whole-body call.
        let sent = try #require(MockGeminiTransport.requests.first { $0.value(forHTTPHeaderField: "Accept") == "application/json" })
        #expect(sent.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
        #expect(sent.value(forHTTPHeaderField: "Accept") == "application/json", "no event stream")
        #expect(sent.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        let body = try #require(sent.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["stream"] as? Bool == false)
        #expect(json["store"] as? Bool == false)
        let interaction = try await client.interact(streamed)
        #expect(interaction.functionCalls.map(\.name) == ["narrative", "done"])
    }

    @Test func sendMapsErrorsAndTimesOut() async {
        let failing = MockGeminiTransport.client(status: 400, body: #"{"error":{"message":"bad schema"}}"#)
        await #expect(throws: GeminiError.http(status: 400, body: #"{"error":{"message":"bad schema"}}"#)) { try await failing.send(request) }
        let errorBody = MockGeminiTransport.client(status: 200, body: #"{"error":{"message":"quota"}}"#)
        await #expect(throws: GeminiError.response("quota")) { try await errorBody.interact(request) }
        MockGeminiTransport.handler = { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return (200, Data(InteractionResponseTests.planBody.utf8))
        }
        MockGeminiTransport.requests = []
        let slow = GeminiClient(apiKey: "test-key", session: MockGeminiTransport.session())
        await #expect(throws: GeminiError.timeout) { try await slow.send(request, timeout: .milliseconds(50)) }
    }

    /// A whole-body reply holding `text` as its one `model_output` part.
    private func body(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"id\":\"int_3\",\"status\":\"completed\",\"steps\":[{\"type\":\"model_output\",\"content\":[{\"type\":\"text\",\"text\":\"\(escaped)\"}]}],\"usage\":{\"total_input_tokens\":200,\"total_output_tokens\":9,\"total_thought_tokens\":0}}"
    }


    @Test func theReaderCallsADifferentSubstanceARewrite() async throws {
        let client = MockGeminiTransport.client(status: 200, body: body(#"{"query":"can you pull up youtube?"}"#))
        let summary = await QueryReader(client: client).read("Which oh can you pull up youtube?")
        #expect(summary.outcome == .rewritten)
        #expect(summary.changed)
        #expect(summary.query == "can you pull up youtube?")
        #expect(summary.original == "Which oh can you pull up youtube?")
        #expect(summary.model == GeminiClient.defaultModel)
        #expect(summary.usage == AnswerUsage(inputTokens: 200, outputTokens: 9, thoughtTokens: 0))
        #expect(summary.latencyMs >= 0)
        let sent = try #require(MockGeminiTransport.requests.compactMap { $0.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }.first { ($0["system_instruction"] as? String) == QueryReader.system })
        #expect((sent["input"] as? String)?.hasSuffix("Request: Which oh can you pull up youtube?") == true)
        #expect((sent["input"] as? String)?.contains("Today: ") == true)
    }

    @Test func theReaderLeavesTheSameWordsUnchanged() async {
        let client = MockGeminiTransport.client(status: 200, body: body(#"{"query":"Capital of Peru"}"#))
        let summary = await QueryReader(client: client).read("capital of peru?")
        #expect(summary.outcome == .unchanged)
        #expect(!summary.changed)
        #expect(summary.query == "Capital of Peru")
    }

    @Test func theReaderFailsOnNothingUsable() async {
        let empty = await QueryReader(client: MockGeminiTransport.client(status: 200, body: body(#"{"query":"  "}"#))).read("x")
        #expect(empty.outcome == .failed("no query") && empty.query == nil)
        let notObject = await QueryReader(client: MockGeminiTransport.client(status: 200, body: body("just words"))).read("x")
        #expect({ if case .failed = notObject.outcome { true } else { false } }())
        let denied = await QueryReader(client: MockGeminiTransport.client(status: 401, body: #"{"error":{"message":"API key not valid"}}"#)).read("x")
        #expect({ if case .failed = denied.outcome { true } else { false } }())
    }

    private let thermostat = ValueExtractorTests.thermostat

    @Test func theExtractorReadsValuesWithoutNulls() async {
        let client = MockGeminiTransport.client(status: 200, body: body(#"{"temperature": 68, "room": null}"#))
        let verdict = await ValueExtractor(client: client).extract(query: "set it to 68", exchanges: [], schema: thermostat)
        guard case let .values(values, summary) = verdict else {
            Issue.record("expected values, got \(verdict)")
            return
        }
        #expect(values == ["temperature": 68])
        #expect(summary.outcome == .extracted)
        #expect(summary.fields == ["temperature"])
        #expect(summary.usage == AnswerUsage(inputTokens: 200, outputTokens: 9, thoughtTokens: 0))
        #expect(summary.model == GeminiClient.defaultModel)
        #expect(summary.latencyMs >= 0)
        // A slow test's request can land in the list late; find this one by its schema.
        let sent = MockGeminiTransport.requests
            .compactMap { $0.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
            .first { $0["response_format"] != nil }
        #expect(sent?["stream"] as? Bool == false)
        #expect((sent?["response_format"] as? [String: Any])?["mime_type"] as? String == "application/json")
    }

    @Test func theExtractorCallsProseAnEmptyObjectAndAFailureMisses() async {
        let prose = MockGeminiTransport.client(status: 200, body: body("I think 68 degrees."))
        if case let .failed(summary) = await ValueExtractor(client: prose).extract(query: "x", exchanges: [], schema: thermostat), case let .failed(reason) = summary.outcome {
            #expect(reason.hasPrefix("not an object"))
        } else {
            Issue.record("prose is a failure")
        }
        let empty = MockGeminiTransport.client(status: 200, body: body(#"{"temperature": null, "room": null}"#))
        if case let .failed(summary) = await ValueExtractor(client: empty).extract(query: "x", exchanges: [], schema: thermostat) {
            #expect(summary.outcome == .empty)
            #expect(summary.usage?.inputTokens == 200)
        } else {
            Issue.record("nothing read is empty")
        }
        let http = MockGeminiTransport.client(status: 400, body: "bad schema")
        if case let .failed(summary) = await ValueExtractor(client: http).extract(query: "x", exchanges: [], schema: thermostat) {
            #expect(summary.outcome == .failed("http 400: bad schema"))
        } else {
            Issue.record("an HTTP error is a failure")
        }
        let failed = MockGeminiTransport.client(status: 200, body: #"{"id":"x","status":"failed","steps":[]}"#)
        if case let .failed(summary) = await ValueExtractor(client: failed).extract(query: "x", exchanges: [], schema: thermostat) {
            #expect(summary.outcome == .failed("status failed"))
        } else {
            Issue.record("a failed status is a failure")
        }
    }

    @Test func thePlannerReadsTheCallsAndMapsAFailure() async throws {
        let client = MockGeminiTransport.client(status: 200, body: InteractionResponseTests.planBody)
        let planner = Planner(client: client)
        let bundle = PlanBundle(query: "q", exchanges: [], facts: [], tools: Planner.tools(for: InstinctSpec.all), context: .example)
        let round = await planner.propose(bundle, transcript: [.userText("Request: q")])
        guard case let .calls(calls, steps, usage, _) = round else {
            Issue.record("expected calls, got \(round)")
            return
        }
        #expect(calls.map(\.name) == ["narrative", "done"])
        #expect(steps.count == 4, "every model step kept for replay")
        #expect(usage == AnswerUsage(inputTokens: 300, outputTokens: 20, thoughtTokens: 5))
        let sent = try #require(MockGeminiTransport.requests.first { $0.value(forHTTPHeaderField: "Accept") == "application/json" })
        let body = try #require(sent.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((json["tools"] as? [[String: Any]])?.count == InstinctSpec.all.count + 6)

        let silent = Planner(client: MockGeminiTransport.client(status: 200, body: #"{"id":"x","status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"I would do this"}]}]}"#))
        guard case .silent(_, _, _, false) = await silent.propose(bundle, transcript: [.userText("Request: q")]) else {
            Issue.record("prose and no calls is silent")
            return
        }
        let starved = Planner(client: MockGeminiTransport.client(status: 200, body: #"{"id":"x","status":"incomplete","steps":[]}"#))
        guard case .silent(_, _, _, true) = await starved.propose(bundle, transcript: [.userText("Request: q")]) else {
            Issue.record("an incomplete round with no call is marked, so the executor asks once more")
            return
        }
        #expect(Planner.request(bundle: bundle, transcript: []).maxOutputTokens == 8000, "the budget counts the thinking: room for a rewrite")
        let failed = Planner(client: MockGeminiTransport.client(status: 400, body: #"{"error":{"message":"bad tool"}}"#))
        guard case let .failed(reason, _) = await failed.propose(bundle, transcript: [.userText("Request: q")]) else {
            Issue.record("an HTTP error fails the round")
            return
        }
        #expect(reason.contains("400"))
    }

    @Test func theExtractorGivesUpAtItsBudget() async {
        MockGeminiTransport.handler = { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return (200, Data(#"{"status":"completed","steps":[]}"#.utf8))
        }
        MockGeminiTransport.requests = []
        let extractor = ValueExtractor(client: GeminiClient(apiKey: "test-key", session: MockGeminiTransport.session()), timeout: .milliseconds(50))
        if case let .failed(summary) = await extractor.extract(query: "x", exchanges: [], schema: thermostat) {
            #expect(summary.outcome == .failed("timeout"))
            #expect(summary.latencyMs < 250, "gave up at the budget, not at the reply")
        } else {
            Issue.record("a slow reply is a timeout")
        }
    }

    @Test func slowHeadersTimeOut() async {
        MockGeminiTransport.handler = { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return (200, Data(answerStream.utf8))
        }
        MockGeminiTransport.requests = []
        let client = GeminiClient(apiKey: "test-key", firstByteTimeout: .milliseconds(50), session: MockGeminiTransport.session())
        let (events, error) = await collect(client, request)
        #expect(events.isEmpty)
        #expect(error == .timeout)
    }
}
