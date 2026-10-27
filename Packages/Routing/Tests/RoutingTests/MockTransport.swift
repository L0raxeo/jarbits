import Foundation
@testable import Routing

/// Serves canned responses to `JevClient` so the tests never touch the network.
final class MockTransport: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (status: Int, body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTransport.self]
        return URLSession(configuration: configuration)
    }

    static func client(status: Int, body: String) -> JevClient {
        handler = { _ in (status, Data(body.utf8)) }
        requests = []
        return JevClient(apiKey: "sk-test", session: session())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        // URLSession streams the body; read it back so tests can inspect it.
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
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A response in the shape TypeSafe documents, with `format` as the question
/// id. `relevance` answers the per-exchange questions `x0`, `x1`, … in order;
/// `reasoning` answers the score.
func jevResponse(
    choice: String, confidence: Double, probabilities: [String: Double],
    recency: Double? = nil, rejects: Double? = nil, relevance: [Double]? = nil,
    reasoning: (score: Double, confidence: Double)? = nil,
    nouls: [String: Double] = [:], model: String = "jev-1.13.0"
) -> String {
    let probs = probabilities.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", ")
    var extra = (recency.map { ", \"recent\": { \"type\": \"noul\", \"noul\": \($0) }" } ?? "")
        + (rejects.map { ", \"rejects\": { \"type\": \"noul\", \"noul\": \($0) }" } ?? "")
        + nouls.sorted { $0.key < $1.key }.map { ", \"\($0.key)\": { \"type\": \"noul\", \"noul\": \($0.value) }" }.joined()
    for (index, value) in (relevance ?? []).enumerated() {
        extra += ", \"\(EngineRouting.relevanceQuestionID(index))\": { \"type\": \"noul\", \"noul\": \(value) }"
    }
    if let reasoning {
        let level = Int(reasoning.score.rounded())
        extra += ", \"\(EngineRouting.reasoningQuestionID)\": { \"type\": \"score\", \"score\": \(reasoning.score), \"confidence\": \(reasoning.confidence), \"probabilities\": { \"\(level)\": \(reasoning.confidence) } }"
    }
    return """
    {
      "model": "\(model)",
      "answers": {
        "format": {
          "type": "choice",
          "choice": "\(choice)",
          "confidence": \(confidence),
          "probabilities": { \(probs) }
        }\(extra)
      },
      "usage": { "input_tokens": 512, "output_tokens": 9 }
    }
    """
}

/// The seven recall answers, yes as 1 and no as 0, keyed by question id.
func recallNouls(kinds: Set<RecallIntent.Kind> = [], named: Bool, all: Bool) -> [String: Double] {
    var answers: [String: Double] = [:]
    for kind in RecallIntent.Kind.allCases { answers[EngineRouting.recallKindQuestionID(kind)] = kinds.contains(kind) ? 1 : 0 }
    answers[EngineRouting.recallNamedQuestionID] = named ? 1 : 0
    answers[EngineRouting.recallAllQuestionID] = all ? 1 : 0
    return answers
}

/// A thread on screen, as exchanges: one answer exchange per turn.
func answerExchanges(_ pairs: [(query: String, answer: String)]) -> [Exchange] {
    pairs.map { .answer(query: $0.query, text: $0.answer) }
}
