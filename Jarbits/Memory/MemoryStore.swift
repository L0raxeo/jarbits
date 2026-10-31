import Foundation
import Answers
import Engine

/// The memories file: every result the user saw, so a `recall` query can
/// bring one back. JSON Lines beside the decision log, loaded once, appended
/// as results appear. A repeat of the same thing within a day refreshes its
/// date instead of adding a line; a short-term memory goes a week after it
/// was last touched (`flush`), a kept one stays until forgotten; past
/// `capacity` the oldest go regardless. A page memory may have a picture
/// beside the file, `<id>.jpg` in `memories/`, kept for the newest
/// `pictureCapacity` pages (kept memories exempt) and deleted with the
/// record. Lines in the flat shape from before parts read through the
/// record's own decoder and are rewritten in the current shape as records
/// are refreshed. Beside the file, `memories.index` keeps the meaning of
/// each record (`MeaningIndex`, Gemini's embedding of its title, query,
/// host and first words), so a request finds a memory by what it is about
/// and not only by the words they share; the index is filled as records
/// are kept, caught up on first use for anything missed, and never the
/// truth: the file is. Nothing in the file leaves the phone; a record's
/// text goes to Gemini once, to be embedded.
actor MemoryStore {
    /// With Gemini's embedder when a key is configured; the session's default.
    @MainActor static let shared = MemoryStore(embedder: Secrets.geminiAPIKey.map { GeminiEmbedder(apiKey: $0) })

    nonisolated let fileURL: URL
    nonisolated let picturesURL: URL
    nonisolated let indexURL: URL
    /// The meaning beside the file; nil without an embedder (no Gemini key).
    private let index: MeaningIndex?
    /// The first catch-up of the index after a load; awaited before a look.
    private var backfill: Task<Void, Never>?
    /// Records kept; at a few hundred bytes each (a few KB for a narrative)
    /// the file stays well under a hundred megabytes.
    static let capacity = 5_000
    /// Page pictures kept, newest first; at about 30 KB each, tens of MB.
    static let pictureCapacity = 1_000
    /// Seeing the same thing again within this refreshes the record.
    static let repeatWindow: TimeInterval = 86_400

    /// Expired memories are looked for at most this often.
    static let flushInterval: TimeInterval = 86_400

    private var loaded: [MemoryRecord]?
    private var lastFlush: Date?

    init(fileURL: URL? = nil, embedder: (any Embedder)? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            // "Browser" is the project's old name, kept: the files already on the phone are there.
            let support = URL.applicationSupportDirectory.appending(path: "Browser", directoryHint: .isDirectory)
            self.fileURL = support.appending(path: "memories.jsonl")
        }
        picturesURL = self.fileURL.deletingLastPathComponent().appending(path: "memories", directoryHint: .isDirectory)
        let indexURL = self.fileURL.deletingLastPathComponent().appending(path: "memories.index")
        self.indexURL = indexURL
        index = embedder.map { MeaningIndex(fileURL: indexURL, embedder: $0) }
    }

    /// Keeps the record and returns the id kept: the existing record's on a
    /// repeat, so a picture taken afterwards lands on it.
    @discardableResult
    func remember(_ record: MemoryRecord) async -> UUID {
        await flushIfDue(now: record.date)
        var all = records()
        if let i = all.lastIndex(where: { $0.sameThing(as: record) && abs(record.date.timeIntervalSince($0.date)) < Self.repeatWindow }) {
            // The same thing again: the date and the title move on, and the
            // parts when the new record has at least as many (a conversation
            // that grew, a page whose title settled). Where it came from and
            // whether it is kept are left as they were.
            all[i].date = record.date
            all[i].title = record.title
            if record.parts.count >= all[i].parts.count { all[i].parts = record.parts }
            // Jarbits's own only while every sighting was its: once the user saw it, theirs.
            all[i].own = (all[i].own == true && record.own == true) ? true : nil
            loaded = all
            rewrite(all)
            let merged = all[i]
            await index?.index(merged.id, text: merged.indexText)
            return merged.id
        }
        all.append(record)
        var dropped: [MemoryRecord] = []
        if all.count > Self.capacity {
            dropped = Array(all.prefix(all.count - Self.capacity))
            all.removeFirst(dropped.count)
            loaded = all
            rewrite(all)
            for old in dropped { try? FileManager.default.removeItem(at: pictureURL(for: old.id)) }
        } else {
            loaded = all
            append(record)
        }
        prunePictures(all)
        // The meaning last, once the file holds the record; a failed embed
        // (offline) is caught up on at the next look.
        if !dropped.isEmpty { await index?.remove(dropped.map(\.id)) }
        await index?.index(record.id, text: record.indexText)
        return record.id
    }

    nonisolated func pictureURL(for id: UUID) -> URL {
        picturesURL.appending(path: "\(id.uuidString).jpg")
    }

    func savePicture(_ data: Data, for id: UUID) {
        do {
            try FileManager.default.createDirectory(at: picturesURL, withIntermediateDirectories: true)
            try data.write(to: pictureURL(for: id), options: .atomic)
        } catch {
            print("MemoryStore: \(error)")
        }
    }

    /// Pictures beyond the newest `pictureCapacity` short-term page
    /// memories go; a kept memory keeps its picture.
    private func prunePictures(_ all: [MemoryRecord]) {
        let pages = all.filter { $0.kind == .page && $0.kept == nil }
        guard pages.count > Self.pictureCapacity else { return }
        for old in pages.sorted(by: { $0.date > $1.date }).dropFirst(Self.pictureCapacity) {
            try? FileManager.default.removeItem(at: pictureURL(for: old.id))
        }
    }

    /// Short-term memories untouched for a week go, with their pictures.
    /// Run on first load and then at most once a day, from `remember`.
    @discardableResult
    func flush(now: Date = .now) async -> Int {
        lastFlush = now
        let all = records()
        let gone = all.filter { $0.expires(by: now) }
        guard !gone.isEmpty else { return 0 }
        let keptRecords = all.filter { !$0.expires(by: now) }
        loaded = keptRecords
        rewrite(keptRecords)
        for old in gone { try? FileManager.default.removeItem(at: pictureURL(for: old.id)) }
        await index?.remove(gone.map(\.id))
        return gone.count
    }

    private func flushIfDue(now: Date) async {
        if let lastFlush, now.timeIntervalSince(lastFlush) < Self.flushInterval { return }
        await flush(now: now)
    }

    /// Long-term from now on: never flushed, its picture never pruned.
    func keep(_ id: UUID, at date: Date = .now) {
        var all = records()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].kept = date
        loaded = all
        rewrite(all)
    }

    /// Gone, with its picture and its meaning.
    func forget(_ id: UUID) async {
        var all = records()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all.remove(at: i)
        loaded = all
        rewrite(all)
        try? FileManager.default.removeItem(at: pictureURL(for: id))
        await index?.remove(id)
    }

    func search(topic: String) -> [MemoryRecord] {
        MemorySearch.matches(records(), topic: topic)
    }

    /// The candidates for a recall: the records the ask allows, the
    /// nearest the topic in meaning first when the index can say, taking
    /// turns with the word matches, then recency; see `MemorySearch.shortlist`.
    func shortlist(topic: String?, ask: RecallAsk = RecallAsk()) async -> [MemoryRecord] {
        let all = records()
        var ranked: [UUID] = []
        if let index, let topic, !MemorySearch.terms(of: topic).isEmpty, ask.count == nil {
            await caughtUp()
            ranked = await index.nearest(to: topic, limit: MemorySearch.limit).map(\.id)
        }
        return MemorySearch.shortlist(all, topic: topic, ask: ask, ranked: ranked)
    }

    /// The records nearest a request in meaning, nearest first, topped up
    /// with the newest to `limit`; the newest alone without an index or
    /// when the request cannot be embedded (offline).
    func nearest(to text: String, limit: Int) async -> [MemoryRecord] {
        let all = records()
        let newest = all.sorted { $0.date > $1.date }
        var out: [MemoryRecord] = []
        if let index {
            await caughtUp()
            let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            out = await index.nearest(to: text, limit: limit).compactMap { byID[$0.id] }
        }
        let have = Set(out.map(\.id))
        for record in newest where out.count < limit && !have.contains(record.id) { out.append(record) }
        return out
    }

    /// The index holds every record once this returns: the first look after
    /// a load embeds whatever was kept before the index existed, or while
    /// offline, in batches.
    private func caughtUp() async {
        guard let index else { return }
        if backfill == nil {
            let items = records().map { (id: $0.id, text: $0.indexText) }
            backfill = Task { await index.backfill(items) }
        }
        await backfill?.value
        backfill = nil   // the next look checks again, cheaply, for anything missed since
    }

    /// Everything goes: the file, every picture and the index. Debug builds
    /// offer this from the idle screen; there is no user-facing control yet.
    func clear() async {
        loaded = []
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: picturesURL)
        await index?.removeAll()
    }

    func all() -> [MemoryRecord] {
        records()
    }

    func record(id: UUID) -> MemoryRecord? {
        records().first { $0.id == id }
    }

    private func records() -> [MemoryRecord] {
        if let loaded { return loaded }
        var read: [MemoryRecord] = []
        if let data = try? Data(contentsOf: fileURL) {
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
                // A line that will not decode (an older shape) is skipped, not fatal.
                if let record = try? DecisionRecord.decoder.decode(MemoryRecord.self, from: Data(line.utf8)) {
                    read.append(record)
                }
            }
        }
        loaded = read
        if lastFlush == nil {
            // The first flush: expired records go now; their meanings go
            // with the next catch-up, which only ever adds, so a stale entry
            // in the index is harmless and is dropped at the next remove.
            lastFlush = .now
            let gone = read.filter { $0.expires(by: .now) }
            if !gone.isEmpty {
                let kept = read.filter { !$0.expires(by: .now) }
                loaded = kept
                rewrite(kept)
                for old in gone { try? FileManager.default.removeItem(at: pictureURL(for: old.id)) }
                if let index { Task { await index.remove(gone.map(\.id)) } }
            }
        }
        return loaded ?? read
    }

    private func append(_ record: MemoryRecord) {
        do {
            var line = try DecisionRecord.encoder.encode(record)
            line.append(UInt8(ascii: "\n"))
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // `path(percentEncoded: false)`, as in `DecisionLog`: the encoded
            // form never exists, and the empty write would wipe the file.
            if !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                try Data().write(to: fileURL)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            // A failed memory must never affect the result itself.
            print("MemoryStore: \(error)")
        }
    }

    private func rewrite(_ all: [MemoryRecord]) {
        do {
            var data = Data()
            for record in all {
                data.append(try DecisionRecord.encoder.encode(record))
                data.append(UInt8(ascii: "\n"))
            }
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("MemoryStore: \(error)")
        }
    }
}
