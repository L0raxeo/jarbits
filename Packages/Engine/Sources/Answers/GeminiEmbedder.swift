import Foundation
import Engine

/// Gemini's embedding model as the meaning index's embedder: one request
/// per text, or one per hundred for a backfill, each answered with the
/// vector of the text's meaning. A thing kept is embedded as a document
/// and a request as a query, Google's two task types, so "that car page"
/// lands near a car maker's page. Nothing is kept by Google (`store` is
/// not a thing here; embeddings are stateless). Nil on any failure: the
/// index then treats the text as unread and catches up later. No retries.
public struct GeminiEmbedder: Embedder {
    public static let defaultModel = "gemini-embedding-001"
    /// The vector's length: Google's model gives 3072 and documents 768
    /// as a sound cut; cosine does not mind the scale.
    public static let dimensions = 768
    /// Texts per batch request, Google's ceiling.
    public static let batch = 100

    public var apiKey: String
    public var baseURL: URL
    public var model: String
    public var timeout: Duration
    var session: URLSession

    public init(apiKey: String, baseURL: URL = GeminiClient.defaultBaseURL, model: String = GeminiEmbedder.defaultModel, timeout: Duration = .seconds(15), session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.timeout = timeout
        self.session = session
    }

    public func vector(for text: String, as use: EmbeddingUse) async -> [Float]? {
        let body: [String: Any] = Self.body(text, use: use, model: model)
        guard let data = await post("v1beta/models/\(model):embedContent", body: body) else { return nil }
        return Self.vector(in: data)
    }

    public func vectors(for texts: [String], as use: EmbeddingUse) async -> [[Float]?] {
        var out: [[Float]?] = []
        for start in stride(from: 0, to: texts.count, by: Self.batch) {
            let slice = Array(texts[start ..< min(start + Self.batch, texts.count)])
            let body: [String: Any] = ["requests": slice.map { Self.body($0, use: use, model: model) }]
            if let data = await post("v1beta/models/\(model):batchEmbedContents", body: body) {
                let found = Self.vectors(in: data)
                out += found.count == slice.count ? found : Array(repeating: nil, count: slice.count)
            } else {
                out += Array(repeating: nil, count: slice.count)
            }
        }
        return out
    }

    // MARK: The request and the reply

    static func body(_ text: String, use: EmbeddingUse, model: String) -> [String: Any] {
        [
            "model": "models/\(model)",
            "content": ["parts": [["text": text]]],
            "taskType": use == .kept ? "RETRIEVAL_DOCUMENT" : "RETRIEVAL_QUERY",
            "outputDimensionality": dimensions,
        ]
    }

    static func vector(in data: Data) -> [Float]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return values(in: object["embedding"])
    }

    static func vectors(in data: Data) -> [[Float]?] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddings = object["embeddings"] as? [Any] else { return [] }
        return embeddings.map(values(in:))
    }

    private static func values(in embedding: Any?) -> [Float]? {
        guard let embedding = embedding as? [String: Any], let values = embedding["values"] as? [Double], !values.isEmpty else { return nil }
        return values.map { Float($0) }
    }

    private func post(_ path: String, body: [String: Any]) async -> Data? {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = encoded
        let prepared = request
        do {
            let (data, response) = try await withTimeout(timeout) { [session] in try await session.data(for: prepared) }
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                #if DEBUG
                print("GeminiEmbedder: \((response as? HTTPURLResponse)?.statusCode ?? 0) \(String(decoding: data.prefix(200), as: UTF8.self))")
                #endif
                return nil
            }
            return data
        } catch {
            #if DEBUG
            print("GeminiEmbedder: \(error)")
            #endif
            return nil
        }
    }
}
