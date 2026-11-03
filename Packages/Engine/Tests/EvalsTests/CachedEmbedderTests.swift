import Foundation
import Testing
@testable import Evals
@testable import Engine

private struct CountingEmbedder: Embedder {
    let counter: Counter
    func vector(for text: String, as use: EmbeddingUse) async -> [Float]? {
        await counter.bump()
        return [Float(text.count), 1]
    }
}

private actor Counter {
    var calls = 0
    func bump() { calls += 1 }
}

@Suite struct CachedEmbedderTests {
    @Test func aVectorIsAskedOnceAndServedFromDiskAfter() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = Counter()
        let cached = CachedEmbedder(inner: CountingEmbedder(counter: counter), directory: directory)
        #expect(await cached.vector(for: "hello", as: .request) == [5, 1])
        #expect(await cached.vector(for: "hello", as: .request) == [5, 1])
        #expect(await counter.calls == 1, "the second comes from the file")
        #expect(await cached.vector(for: "hello", as: .kept) == [5, 1])
        #expect(await counter.calls == 2, "a different use is a different key")
        let offline = CachedEmbedder(inner: nil, directory: directory)
        #expect(await offline.vector(for: "hello", as: .request) == [5, 1], "cached, no inner needed")
        #expect(await offline.vector(for: "other", as: .request) == nil, "not cached, nothing asked")
    }
}
