import CryptoKit
import Foundation
import Routing

/// Jev's answers on disk, one file per request body, so a run that changes
/// nothing Jev sees asks nothing. The key is a hash of the body: the model,
/// the locale, every instruction and criterion, the thread and the opened
/// site are all in it, so an edit to any of them re-asks by itself; the
/// thresholds are not, so a sweep is free. A model change orphans the old
/// files; delete the directory to start over.
public struct JevCache: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// One cached answer: the response as the server sent it, and when and
    /// how fast it came.
    public struct Entry: Decodable, Sendable {
        public var date: Date
        public var latencyMs: Int
        public var model: String
        public var query: String
        public var response: SystemOneResponse

        enum CodingKeys: String, CodingKey {
            case date, model, query, response
            case latencyMs = "latency_ms"
        }
    }

    /// Hex SHA-256 of the request body, as `JevClient` sends it.
    public static func key(for request: SystemOneRequest) throws -> String {
        SHA256.hash(data: try request.jsonData()).map { String(format: "%02x", $0) }.joined()
    }

    public func fileURL(for key: String) -> URL {
        directory.appending(path: "\(key).json")
    }

    /// Nil when there is no file or it cannot be read as an entry.
    public func entry(for key: String) -> Entry? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Entry.self, from: data)
    }

    /// `response` is the body verbatim; it must already have decoded, so
    /// the file is one JSON object a reader and `grep` can both use.
    public func store(key: String, request: SystemOneRequest, response: Data, latencyMs: Int, date: Date = .now) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = try OrderedJSON.object([
            ("date", OrderedJSON.encode(ISO8601DateFormatter().string(from: date))),
            ("latency_ms", OrderedJSON.encode(latencyMs)),
            ("model", OrderedJSON.encode(request.model)),
            ("query", OrderedJSON.encode(request.state.query)),
            ("response", response),
        ])
        try file.write(to: fileURL(for: key), options: .atomic)
    }
}
