import Foundation
import Testing
import Engine
@testable import Answers

// Nested in the client's serialized suite: both drive the one mock transport.
extension GeminiClientTests {
@Suite struct GeminiEmbedderTests {
    private func embedder(status: Int = 200, body: String) -> GeminiEmbedder {
        MockGeminiTransport.handler = { _ in (status, Data(body.utf8)) }
        MockGeminiTransport.requests = []
        return GeminiEmbedder(apiKey: "test-key", timeout: .seconds(5), session: MockGeminiTransport.session())
    }

    @Test func aRequestIsAQueryAndAKeptThingIsADocument() async throws {
        let embedder = embedder(body: #"{"embedding":{"values":[0.1,0.2,0.3]}}"#)
        let vector = await embedder.vector(for: "add this to my watchlist", as: .request)
        #expect(vector == [0.1, 0.2, 0.3])
        let request = try #require(MockGeminiTransport.requests.first)
        #expect(request.url?.path() == "/v1beta/models/gemini-embedding-001:embedContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        let sent = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(sent["taskType"] as? String == "RETRIEVAL_QUERY")
        #expect(sent["outputDimensionality"] as? Int == 768)
        #expect(sent["model"] as? String == "models/gemini-embedding-001")
        #expect(((sent["content"] as? [String: Any])?["parts"] as? [[String: String]])?.first?["text"] == "add this to my watchlist")
        _ = await embedder.vector(for: "Watch List", as: .kept)
        let kept = try #require(try JSONSerialization.jsonObject(with: MockGeminiTransport.requests.last?.httpBody ?? Data()) as? [String: Any])
        #expect(kept["taskType"] as? String == "RETRIEVAL_DOCUMENT")
    }

    @Test func aBatchGoesInOneRequestAndComesBackInOrder() async throws {
        let embedder = embedder(body: #"{"embeddings":[{"values":[1,0]},{"values":[0,1]}]}"#)
        let vectors = await embedder.vectors(for: ["Watch List", "Shopping"], as: .kept)
        #expect(vectors == [[1, 0], [0, 1]])
        #expect(MockGeminiTransport.requests.count == 1)
        #expect(MockGeminiTransport.requests[0].url?.path() == "/v1beta/models/gemini-embedding-001:batchEmbedContents")
        let sent = try #require(try JSONSerialization.jsonObject(with: MockGeminiTransport.requests[0].httpBody ?? Data()) as? [String: Any])
        #expect((sent["requests"] as? [Any])?.count == 2)
    }

    @Test func aFailureIsNilNeverAThrow() async {
        let failing = embedder(status: 500, body: #"{"error":"no"}"#)
        #expect(await failing.vector(for: "x", as: .request) == nil)
        #expect(await failing.vectors(for: ["x", "y"], as: .kept) == [nil, nil])
        let odd = embedder(body: #"{"embeddings":[{"values":[1]}]}"#)
        #expect(await odd.vectors(for: ["x", "y"], as: .kept) == [nil, nil], "a reply of the wrong length is trusted for none")
        #expect(GeminiEmbedder.vector(in: Data(#"{"embedding":{"values":[]}}"#.utf8)) == nil)
    }
}
}
