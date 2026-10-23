import Foundation
import Routing

/// The memories file: every result the user saw, so a `recall` query can
/// bring one back. JSON Lines beside the decision log, loaded once, appended
/// as results appear. A repeat of the same thing within a day refreshes its
/// date instead of adding a line; past `capacity` the oldest go. Nothing in
/// it leaves the phone.
actor MemoryStore {
    static let shared = MemoryStore()

    nonisolated let fileURL: URL
    /// Records kept; at a few hundred bytes each (a few KB for a narrative)
    /// the file stays well under a hundred megabytes.
    static let capacity = 5_000
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
    }

    func remember(_ record: MemoryRecord) {
        var all = records()
        if let i = all.lastIndex(where: { $0.sameThing(as: record) && abs(record.date.timeIntervalSince($0.date)) < Self.repeatWindow }) {
            all[i].date = record.date
            all[i].title = record.title
            all[i].text = record.text ?? all[i].text
            loaded = all
            rewrite(all)
            return
        }
        all.append(record)
        if all.count > Self.capacity {
            all.removeFirst(all.count - Self.capacity)
            loaded = all
            rewrite(all)
            return
        }
        loaded = all
        append(record)
    }

    func search(_ query: String) -> [MemoryRecord] {
        MemorySearch.matches(records(), query: query)
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
            if !FileManager.default.fileExists(atPath: fileURL.path()) {
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
