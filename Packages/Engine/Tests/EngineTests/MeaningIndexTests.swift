import Foundation
import Testing
@testable import Engine

/// A stand-in for the model: a text's vector is where its words sit on
/// three made-up axes, so nearness is checkable by hand.
struct FakeEmbedder: Embedder {
    static let axes: [String: [Float]] = [
        "watch": [1, 0, 0], "watchlist": [1, 0, 0], "videos": [0.8, 0, 0.2],
        "shopping": [0, 1, 0], "groceries": [0, 1, 0], "milk": [0, 0.9, 0.1],
        "packing": [0, 0, 1], "trip": [0, 0.1, 0.9],
    ]

    func vector(for text: String, as use: EmbeddingUse) async -> [Float]? {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        let hits = words.compactMap { Self.axes[$0] }
        guard !hits.isEmpty else { return nil }
        return (0 ..< 3).map { i in hits.map { $0[i] }.reduce(0, +) }
    }
}

@Suite struct MeaningIndexTests {
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "meaning-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theNearestComeInOrderOfMeaningNotWords() async {
        let index = MeaningIndex(fileURL: folder().appending(path: "notes.index"), embedder: FakeEmbedder())
        let watch = UUID(), shopping = UUID(), packing = UUID()
        await index.index(watch, text: "Watch List\nvideos to watch")
        await index.index(shopping, text: "Shopping\nmilk, eggs")
        await index.index(packing, text: "Packing list\npassport, charger")
        let near = await index.nearest(to: "add this to my watchlist", limit: 3)
        #expect(near.map(\.id) == [watch, packing, shopping] || near.map(\.id) == [watch, shopping, packing])
        #expect(near[0].closeness > 0.99 && near[1].closeness < 0.2, "the watch list is the meaning; the rest are far")
        #expect(await index.nearest(to: "groceries for the trip", limit: 2).map(\.id) == [shopping, packing])
        #expect(await index.nearest(to: "trip", among: [watch, packing], limit: 5).map(\.id) == [packing, watch], "among narrows the pool; nearness still orders it")
        #expect(await index.nearest(to: "nothing the model knows", limit: 3).isEmpty, "a text the embedder cannot read finds nothing")
        #expect(await index.nearest(to: "milk", limit: 0).isEmpty)
    }

    @Test func removingAndReplacingKeepTheIndexTrue() async {
        let index = MeaningIndex(fileURL: folder().appending(path: "notes.index"), embedder: FakeEmbedder())
        let id = UUID(), other = UUID()
        await index.index(id, text: "Shopping")
        await index.index(other, text: "Packing")
        let hasID = await index.has(id), count = await index.count
        #expect(hasID && count == 2)
        await index.index(id, text: "Watch List")
        #expect(await index.nearest(to: "watchlist", limit: 1).map(\.id) == [id], "the later text replaces the earlier")
        await index.index(id, text: "")
        #expect(await !index.has(id), "an empty text takes the id out")
        await index.index(other, text: "Shopping")
        await index.index(other, text: "nothing the model knows")
        #expect(await index.nearest(to: "groceries", limit: 1).map(\.id) == [other], "a text the model cannot read leaves the earlier meaning")
        await index.remove(other)
        let left = await index.count
        #expect(left == 0)
    }

    @Test func theFileRoundTripsAndBackfillSkipsWhatItHas() async throws {
        let file = folder().appending(path: "memories.index")
        let a = UUID(), b = UUID()
        do {
            let index = MeaningIndex(fileURL: file, embedder: FakeEmbedder())
            await index.index(a, text: "Shopping milk")
            await index.index(b, text: "Packing for the trip")
            await index.flush()
        }
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        let again = MeaningIndex(fileURL: file, embedder: FakeEmbedder())
        let kept = await again.count
        #expect(kept == 2)
        #expect(await again.nearest(to: "groceries", limit: 1).map(\.id) == [a])
        let c = UUID()
        await again.backfill([(id: a, text: "Watch List"), (id: c, text: "Watch List")])
        #expect(await again.nearest(to: "watchlist", limit: 1).map(\.id) == [c], "a is already indexed as shopping and stays so; c is new")
        await again.removeAll()
        let afterRemoveAll = await again.count
        #expect(afterRemoveAll == 0 && !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        // The encoding itself, including a vector of a different length and a bad file.
        let entries: [UUID: [Float]] = [a: [0.5, -1, 3.25], b: [1]]
        #expect(MeaningIndex.decode(MeaningIndex.encode(entries)) == entries)
        #expect(MeaningIndex.decode(Data("not an index".utf8)) == nil)
        #expect(MeaningIndex.decode(MeaningIndex.encode(entries).prefix(20)) == nil, "a cut-off file reads as nothing, not as part")
    }

    @Test func cosineIsOneForTheSameDirectionAndZeroAcross() {
        #expect(MeaningIndex.cosine([1, 0], [2, 0]) == 1)
        #expect(MeaningIndex.cosine([1, 0], [0, 3]) == 0)
        #expect(abs(MeaningIndex.cosine([1, 1], [1, 0]) - 0.7071) < 0.001)
        #expect(MeaningIndex.cosine([1, 0], [1, 0, 0]) == 0, "different lengths never compare")
        #expect(MeaningIndex.cosine([0, 0], [1, 0]) == 0)
    }
}
