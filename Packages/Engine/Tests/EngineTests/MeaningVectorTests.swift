import Foundation
import Testing
@testable import Engine

/// An embedder that knows a few texts: a vector per word, so the tests
/// never touch the network.
private struct StubEmbedder: Embedder {
    let table: [String: [Float]]
    func vector(for text: String, as use: EmbeddingUse) async -> [Float]? { table[text] }
}

@Suite struct MeaningVectorTests {
    @Test func nearestByVectorMatchesNearestByText() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MeaningVectorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = StubEmbedder(table: ["cat": [1, 0, 0], "dog": [0.9, 0.1, 0], "car": [0, 0, 1], "kitten": [0.95, 0.05, 0]])
        let index = MeaningIndex(fileURL: directory.appending(path: "x.index"), embedder: embedder)
        let cat = UUID(), dog = UUID(), car = UUID()
        await index.backfill([(cat, "cat"), (dog, "dog"), (car, "car")])
        let byText = await index.nearest(to: "kitten", limit: 2).map(\.id)
        let byVector = await index.nearest(toVector: [0.95, 0.05, 0], limit: 2).map(\.id)
        #expect(byText == [cat, dog] && byVector == byText)
        #expect(await index.nearest(toVector: [], limit: 2).isEmpty, "no vector, nothing")
        #expect(await index.nearest(toVector: [0, 0, 1], among: [cat, dog], limit: 5).map(\.id).count == 2, "among limits the set")
    }
}
