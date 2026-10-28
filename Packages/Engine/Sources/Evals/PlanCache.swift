import CryptoKit
import Foundation
import Answers
import Engine

/// The planner's first-round answers on disk, one file per request body,
/// keyed like Jev's cache: the model, the prompt, the tools, the listing
/// and the facts are all in the body, so a change to any of them asks
/// again by itself. Delete the directory to start over.
public struct PlanCache: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public struct Entry: Decodable, Sendable {
        public var date: Date
        public var latencyMs: Int
        public var model: String
        public var query: String
        /// The interaction as the server sent it.
        public var response: JSONValue

        enum CodingKeys: String, CodingKey {
            case date, model, query, response
            case latencyMs = "latency_ms"
        }
    }

    public static func key(for request: InteractionRequest) throws -> String {
        SHA256.hash(data: try request.jsonData()).map { String(format: "%02x", $0) }.joined()
    }

    public func fileURL(for key: String) -> URL {
        directory.appending(path: "\(key).json")
    }

    /// The cached response body and its latency; nil when there is none.
    public func entry(for key: String) -> (response: Data, latencyMs: Int)? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entry = try? decoder.decode(Entry.self, from: data), let response = try? entry.response.data() else { return nil }
        return (response, entry.latencyMs)
    }

    public func store(key: String, request: InteractionRequest, query: String, response: Data, latencyMs: Int, date: Date = .now) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = try OrderedJSON.object([
            ("date", OrderedJSON.encode(ISO8601DateFormatter().string(from: date))),
            ("latency_ms", OrderedJSON.encode(latencyMs)),
            ("model", OrderedJSON.encode(request.model)),
            ("query", OrderedJSON.encode(query)),
            ("response", response),
        ])
        try file.write(to: fileURL(for: key), options: .atomic)
    }
}
