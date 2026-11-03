import CryptoKit
import Foundation
import Engine

/// Gemini's embeddings on disk, one file per text and use, so a run that
/// embeds the same requests again asks nothing. Nil inside never touches
/// the network: a miss is nil, and the pick goes without lines.
public struct CachedEmbedder: Embedder {
    public var inner: (any Embedder)?
    public var directory: URL

    public init(inner: (any Embedder)?, directory: URL) {
        self.inner = inner
        self.directory = directory
    }

    public static func key(_ text: String, as use: EmbeddingUse) -> String {
        SHA256.hash(data: Data("\(use)\u{1F}\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func fileURL(_ text: String, as use: EmbeddingUse) -> URL {
        directory.appending(path: "\(Self.key(text, as: use)).json")
    }

    public func vector(for text: String, as use: EmbeddingUse) async -> [Float]? {
        let file = fileURL(text, as: use)
        if let data = try? Data(contentsOf: file), let vector = try? JSONDecoder().decode([Float].self, from: data) { return vector }
        guard let inner, let vector = await inner.vector(for: text, as: use) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(vector).write(to: file, options: .atomic)
        return vector
    }
}
