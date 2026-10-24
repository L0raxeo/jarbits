import Foundation
import Routing

/// The memories file: every result the user saw, so a `recall` query can
/// bring one back. JSON Lines beside the decision log, loaded once, appended
/// as results appear. A repeat of the same thing within a day refreshes its
/// date instead of adding a line; past `capacity` the oldest go. A page
/// memory may have a picture beside the file, `<id>.jpg` in `memories/`,
/// kept for the newest `pictureCapacity` pages and deleted with the
/// record. Nothing in it leaves the phone.
actor MemoryStore {
    static let shared = MemoryStore()

    nonisolated let fileURL: URL
    nonisolated let picturesURL: URL
    /// Records kept; at a few hundred bytes each (a few KB for a narrative)
    /// the file stays well under a hundred megabytes.
    static let capacity = 5_000
    /// Page pictures kept, newest first; at about 30 KB each, tens of MB.
    static let pictureCapacity = 1_000
    /// Seeing the same thing again within this refreshes the record.
    static let repeatWindow: TimeInterval = 86_400

    private var loaded: [MemoryRecord]?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = URL.applicationSupportDirectory.appending(path: "Browser", directoryHint: .isDirectory)
            self.fileURL = support.appending(path: "memories.jsonl")
        }
        picturesURL = self.fileURL.deletingLastPathComponent().appending(path: "memories", directoryHint: .isDirectory)
    }

    /// Keeps the record and returns the id kept: the existing record's on a
    /// repeat, so a picture taken afterwards lands on it.
    @discardableResult
    func remember(_ record: MemoryRecord) -> UUID {
        var all = records()
        if let i = all.lastIndex(where: { $0.sameThing(as: record) && abs(record.date.timeIntervalSince($0.date)) < Self.repeatWindow }) {
            all[i].date = record.date
            all[i].title = record.title
            all[i].text = record.text ?? all[i].text
            all[i].turns = record.turns ?? all[i].turns
            loaded = all
            rewrite(all)
            return all[i].id
        }
        all.append(record)
        if all.count > Self.capacity {
            let dropped = all.prefix(all.count - Self.capacity)
            all.removeFirst(dropped.count)
            loaded = all
            rewrite(all)
            for old in dropped { try? FileManager.default.removeItem(at: pictureURL(for: old.id)) }
        } else {
            loaded = all
            append(record)
        }
        prunePictures(all)
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

    /// Pictures beyond the newest `pictureCapacity` page memories go.
    private func prunePictures(_ all: [MemoryRecord]) {
        let pages = all.filter { $0.kind == .page }
        guard pages.count > Self.pictureCapacity else { return }
        for old in pages.sorted(by: { $0.date > $1.date }).dropFirst(Self.pictureCapacity) {
            try? FileManager.default.removeItem(at: pictureURL(for: old.id))
        }
    }

    func search(_ query: String) -> [MemoryRecord] {
        MemorySearch.matches(records(), query: query)
    }

    /// The candidates for a recall: filtered by the query's kind and time
    /// words, ranked by words then recency; see `MemorySearch.shortlist`.
    /// `intent` is Jev's reading of the ask from the routing decision; nil
    /// leaves the word lists to decide.
    func shortlist(_ query: String, now: Date = .now, intent: RecallIntent? = nil) -> [MemoryRecord] {
        MemorySearch.shortlist(records(), query: query, now: now, intent: intent)
    }

    /// Everything goes: the file and every picture. Debug builds offer this
    /// from the idle screen; there is no user-facing control yet.
    func clear() {
        loaded = []
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: picturesURL)
    }

    func all() -> [MemoryRecord] {
        records()
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
        return read
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
