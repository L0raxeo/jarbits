import Foundation

/// Turns a piece of English into a list of numbers whose direction is its
/// meaning, so two texts that mean alike point alike ("watchlist" and
/// "Watch List", "that car page" and a car maker's site). Nil when it
/// cannot: an empty text, no network, no model. Which model is the app's
/// choice: Gemini's (`GeminiEmbedder` in the Answers library). Apple's
/// on-device sentence and word embeddings were measured on 2026-10-28
/// and rank these cases wrong, so neither is it.
public protocol Embedder: Sendable {
    /// What the text is: a thing kept in a store, or the words of a
    /// request looking for one. A model may embed the two differently so
    /// a short request lands near a long thing.
    func vector(for text: String, as use: EmbeddingUse) async -> [Float]?
    /// Several at once, in order, nil where one could not be read; a model
    /// that takes a batch answers in fewer requests.
    func vectors(for texts: [String], as use: EmbeddingUse) async -> [[Float]?]
}

public enum EmbeddingUse: Sendable {
    case kept, request
}

public extension Embedder {
    func vectors(for texts: [String], as use: EmbeddingUse) async -> [[Float]?] {
        var out: [[Float]?] = []
        for text in texts { out.append(await vector(for: text, as: use)) }
        return out
    }
}

/// Meaning kept beside a store: for every note or memory, the vector of
/// its text, so a request can be matched to the things it means rather
/// than to the words it shares with them. Lives in one file beside the
/// store, read once and rewritten whole, a second after the last change
/// (`saveDelay`), atomically; anything missing from it is embedded again
/// on first use, so the file is only ever a cache of the store.
public actor MeaningIndex {
    public nonisolated let fileURL: URL
    private let embedder: any Embedder
    private var entries: [UUID: [Float]]?
    private var saveTask: Task<Void, Never>?

    /// How long after the last change the file is written.
    public static let saveDelay: Duration = .seconds(1)

    public init(fileURL: URL, embedder: any Embedder) {
        self.fileURL = fileURL
        self.embedder = embedder
    }

    // MARK: Keeping

    /// The text's meaning, kept under the id; an earlier one is replaced.
    /// A text the embedder cannot read now (offline, say) leaves the id as
    /// it was, for `backfill` to catch up on; an empty text takes it out.
    public func index(_ id: UUID, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            remove(id)
            return
        }
        guard let vector = await embedder.vector(for: trimmed, as: .kept) else { return }
        var all = load()
        all[id] = vector
        entries = all
        scheduleSave()
    }

    public func remove(_ id: UUID) {
        remove([id])
    }

    public func remove(_ ids: some Sequence<UUID>) {
        var all = load()
        var changed = false
        for id in ids where all.removeValue(forKey: id) != nil { changed = true }
        guard changed else { return }
        entries = all
        scheduleSave()
    }

    public func removeAll() {
        entries = [:]
        saveTask?.cancel()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Indexes whatever is not yet in the index, in batches; the first use
    /// of a store with things kept before the index existed pays this
    /// once, and anything missed while offline is caught up on here.
    public func backfill(_ items: [(id: UUID, text: String)]) async {
        let known = load()
        let missing = items.filter { known[$0.id] == nil && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !missing.isEmpty else { return }
        for start in stride(from: 0, to: missing.count, by: Self.batch) {
            let slice = Array(missing[start ..< min(start + Self.batch, missing.count)])
            let vectors = await embedder.vectors(for: slice.map(\.text), as: .kept)
            var all = load()
            for (item, vector) in zip(slice, vectors) {
                if let vector { all[item.id] = vector }
            }
            entries = all
            scheduleSave()
        }
    }

    /// How many texts go to the embedder at once in a backfill.
    public static let batch = 100

    // MARK: Asking

    public func has(_ id: UUID) -> Bool { load()[id] != nil }

    public var count: Int { load().count }

    public var ids: Set<UUID> { Set(load().keys) }

    /// The ids nearest the text in meaning, nearest first, at most `limit`;
    /// `among` narrows the pool. Empty when the text cannot be read or
    /// nothing is indexed.
    public func nearest(to text: String, among ids: Set<UUID>? = nil, limit: Int) async -> [(id: UUID, closeness: Float)] {
        guard limit > 0, !load().isEmpty, let probe = await embedder.vector(for: text, as: .request) else { return [] }
        var scored: [(id: UUID, closeness: Float)] = []
        for (id, vector) in load() where ids?.contains(id) ?? true {
            scored.append((id, Self.cosine(probe, vector)))
        }
        return Array(scored.sorted { $0.closeness > $1.closeness }.prefix(limit))
    }

    /// How alike two meanings are: 1 the same direction, 0 unrelated.
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    // MARK: The file

    /// Writes the file now, instead of a second from now.
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func load() -> [UUID: [Float]] {
        if let entries { return entries }
        let read = (try? Data(contentsOf: fileURL)).flatMap(Self.decode) ?? [:]
        entries = read
        return read
    }

    private func save() {
        guard let entries else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            print("MeaningIndex: \(error)")
        }
    }

    // A compact binary shape, since a vector is hundreds of numbers: a
    // magic word, then for each entry the id's 16 bytes, the vector's
    // length and its floats, little-endian.
    private static let magic = Data("MIDX".utf8)

    static func encode(_ entries: [UUID: [Float]]) -> Data {
        var data = magic
        data.append(contentsOf: withUnsafeBytes(of: UInt32(entries.count).littleEndian, Array.init))
        for (id, vector) in entries {
            data.append(contentsOf: withUnsafeBytes(of: id.uuid, Array.init))
            data.append(contentsOf: withUnsafeBytes(of: UInt32(vector.count).littleEndian, Array.init))
            for value in vector {
                data.append(contentsOf: withUnsafeBytes(of: value.bitPattern.littleEndian, Array.init))
            }
        }
        return data
    }

    static func decode(_ data: Data) -> [UUID: [Float]]? {
        guard data.count >= magic.count + 4, data.prefix(magic.count) == magic else { return nil }
        var offset = magic.count
        func read<T: FixedWidthInteger>(_: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else { return nil }
            var value: T = 0
            withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: data[offset ..< offset + size]) }
            offset += size
            return T(littleEndian: value)
        }
        guard let count = read(UInt32.self) else { return nil }
        var entries: [UUID: [Float]] = [:]
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            guard offset + 16 <= data.count else { return nil }
            var bytes = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            withUnsafeMutableBytes(of: &bytes) { $0.copyBytes(from: data[offset ..< offset + 16]) }
            offset += 16
            guard let length = read(UInt32.self) else { return nil }
            var vector: [Float] = []
            vector.reserveCapacity(Int(length))
            for _ in 0 ..< length {
                guard let bits = read(UInt32.self) else { return nil }
                vector.append(Float(bitPattern: bits))
            }
            entries[UUID(uuid: bytes)] = vector
        }
        return entries
    }
}
