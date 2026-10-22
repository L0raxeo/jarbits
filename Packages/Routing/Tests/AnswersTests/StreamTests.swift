import Foundation
import Routing
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
