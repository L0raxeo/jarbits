import Foundation
@testable import Answers

/// Serves a canned SSE body to `GeminiClient` so the tests never touch the network.
final class MockGeminiTransport: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (status: Int, body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockGeminiTransport.self]
        return URLSession(configuration: configuration)
    }

    static func client(status: Int, body: String, firstByteTimeout: Duration = .seconds(2), totalTimeout: Duration = .seconds(5)) -> GeminiClient {
        handler = { _ in (status, Data(body.utf8)) }
        requests = []
        return GeminiClient(apiKey: "test-key", firstByteTimeout: firstByteTimeout, totalTimeout: totalTimeout, session: session())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4096)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            request.httpBody = data
        }
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": status < 300 ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A one-line answer in the shape Google documents for the Interactions API stream.
let answerStream = """
event: interaction.created
data: {"event_type":"interaction.created","interaction":{"id":"int_1","status":"in_progress"}}

event: step.start
data: {"event_type":"step.start","index":0,"step":{"type":"model_output","content":[{"type":"text","text":""}]}}

event: step.delta
data: {"event_type":"step.delta","index":0,"delta":{"type":"text","text":"8:14 "}}

event: step.delta
data: {"event_type":"step.delta","index":0,"delta":{"type":"text","text":"PM"}}

event: step.stop
data: {"event_type":"step.stop","index":0,"step":{"type":"model_output","content":[{"type":"text","text":"8:14 PM"}]}}

event: interaction.completed
data: {"event_type":"interaction.completed","interaction":{"id":"int_1","status":"completed","usage":{"total_input_tokens":412,"total_output_tokens":6,"total_thought_tokens":3,"total_tokens":421}}}

event: done
data: [DONE]

"""
