import Foundation
import Routing

/// Streams one answer from Gemini. No retries: a search should not wait,
/// and the app falls back to web results on any failure before text arrives.
public struct GeminiClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com")!
    /// Pinned. If this model rejects `thinking_level: minimal`, move to
    /// `gemini-3.5-flash-lite`, which documents that level; prices in `GeminiPricing`.
    public static let defaultModel = "gemini-3.1-flash-lite"

    public var apiKey: String
    public var baseURL: URL
    public var model: String
    /// Budget for the response headers; a grounded answer searches first.
    public var firstByteTimeout: Duration
    /// Budget for the whole stream.
    public var totalTimeout: Duration
    var session: URLSession

    public init(
        apiKey: String,
        baseURL: URL = GeminiClient.defaultBaseURL,
        model: String = GeminiClient.defaultModel,
        firstByteTimeout: Duration = .seconds(10),
        totalTimeout: Duration = .seconds(30),
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.firstByteTimeout = firstByteTimeout
        self.totalTimeout = totalTimeout
        self.session = session
    }

    public func stream(_ request: InteractionRequest) -> AsyncThrowingStream<AnswerEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withTimeout(totalTimeout) {
                        try await run(request, into: continuation)
                    }
                    continuation.finish()
                } catch is TimeoutError {
                    continuation.finish(throwing: GeminiError.timeout)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ request: InteractionRequest, into continuation: AsyncThrowingStream<AnswerEvent, any Error>.Continuation) async throws {
        var urlRequest = URLRequest(url: baseURL.appending(path: "v1beta/interactions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            urlRequest.httpBody = try request.jsonData()
        } catch {
            throw GeminiError.stream("encode: \(error)")
        }

        let prepared = urlRequest
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await withTimeout(firstByteTimeout) { [session] in
                try await session.bytes(for: prepared)
            }
        } catch is TimeoutError {
            throw GeminiError.timeout
        } catch {
            throw GeminiError.transport(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.transport("not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            var body: [UInt8] = []
            for try await byte in bytes.prefix(500) { body.append(byte) }
            throw GeminiError.http(status: http.statusCode, body: String(decoding: body, as: UTF8.self))
        }

        var parser = SSEParser()
        var line: [UInt8] = []
        func handle(_ event: SSEParser.Event) throws(GeminiError) {
            for answerEvent in try InteractionStream.events(event) {
                continuation.yield(answerEvent)
            }
        }
        do {
            for try await byte in bytes {
                if byte == UInt8(ascii: "\n") {
                    if line.last == UInt8(ascii: "\r") { line.removeLast() }
                    let text = String(decoding: line, as: UTF8.self)
                    line.removeAll(keepingCapacity: true)
                    if let event = parser.feed(line: text) { try handle(event) }
                } else {
                    line.append(byte)
                }
            }
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.transport(String(describing: error))
        }
        if !line.isEmpty, let event = parser.feed(line: String(decoding: line, as: UTF8.self)) { try handle(event) }
        if let event = parser.flush() { try handle(event) }
    }
}
