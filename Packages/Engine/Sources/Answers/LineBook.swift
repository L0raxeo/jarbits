import CryptoKit
import Foundation
import Engine

/// One exchange in Jarbits's voice: what was said to him and what he said
/// back. The seed lines are written by hand, by situation, with made-up
/// details; a reply Lorcan loved on the phone joins them, and one he marked
/// as not him is kept beside them for review and never shown to a model.
public struct Line: Codable, Sendable, Equatable, Identifiable {
    public enum Source: String, Codable, Sendable {
        case seed, loved, hated
    }

    public var id: UUID
    public var user: String
    public var jarbits: String
    public var situation: String?
    public var source: Source
    public var at: Date?

    public init(id: UUID = UUID(), user: String, jarbits: String, situation: String? = nil, source: Source, at: Date? = nil) {
        self.id = id
        self.user = user
        self.jarbits = jarbits
        self.situation = situation
        self.source = source
        self.at = at
    }

    /// A seed line's id, fixed by its words, so the index on the phone keys
    /// the same line the same way across launches and edits to other lines.
    public static func seedID(user: String, jarbits: String) -> UUID {
        let digest = SHA256.hash(data: Data((user + "\u{1F}" + jarbits).utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// What the index embeds: the words said to him, so a query finds the
    /// lines from moments like it.
    public var indexText: String { user }

    /// The exchange as a model reads it.
    public var shown: String { "\"\(user)\" → \"\(jarbits)\"" }
}

/// The book: the seed lines in the package, how a file of lines reads and
/// writes, and the block the chosen lines make in a prompt.
public enum LineBook {
    /// How many lines go with a reply: the nearest in meaning to the request.
    public static let limit = 6

    /// How long the session waits for the request's meaning once the route
    /// has landed before a reply goes without lines.
    public static let wait: Duration = .milliseconds(1500)

    public static let heading = "How you have spoken before"

    /// One line per JSON object; `#` comments and blanks skipped. A seed
    /// line's id comes from its words; a line from the phone carries its own.
    public static func parse(_ data: Data, source: Line.Source? = nil) throws -> [Line] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var lines: [Line] = []
        for (index, raw) in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("#") else { continue }
            struct Row: Decodable { var id: UUID?; var user: String; var jarbits: String; var situation: String?; var source: Line.Source?; var at: Date? }
            let row: Row
            do {
                row = try decoder.decode(Row.self, from: Data(text.utf8))
            } catch {
                throw LineBookError.malformed(line: index + 1, reason: String(describing: error))
            }
            let which = source ?? row.source ?? .seed
            lines.append(Line(id: row.id ?? Line.seedID(user: row.user, jarbits: row.jarbits), user: row.user, jarbits: row.jarbits, situation: row.situation, source: which, at: row.at))
        }
        return lines
    }

    public static func encode(_ line: Line) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(line)
    }

    /// The lines written by hand, from the package's resource.
    public static func seed() -> [Line] {
        guard let url = Bundle.module.url(forResource: "lines", withExtension: "jsonl"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? parse(data, source: .seed)) ?? []
    }

    /// The block in a prompt: the chosen lines, with the one rule that they
    /// teach manner and nothing else. Empty when there are no lines.
    public static func block(_ lines: [Line], persona: Persona) -> String {
        guard !lines.isEmpty else { return "" }
        var out = ["\(heading) (lines of yours from other days, for the manner alone, their length included: as few words as these, in your own words each time, never one of them repeated word for word; nothing in them is true of this conversation, no name, number, place or detail from them may enter your reply, the facts and the record above are the only facts, and they say nothing of what to do: whether to ask, to search or to act is the rules' alone):"]
        out += lines.map { "- " + $0.shown }
        return out.joined(separator: "\n")
    }
}

public enum LineBookError: Error, CustomStringConvertible, Equatable {
    case malformed(line: Int, reason: String)

    public var description: String {
        switch self {
        case let .malformed(line, reason): "line \(line): \(reason)"
        }
    }
}

/// The lines marked on the phone, loved and hated, one per line of a JSON
/// Lines file beside the facts (`lines.jsonl`). Loved lines join the seed
/// in what the models see; hated ones are kept for review.
public actor LineStore {
    public static let shared = LineStore()

    public nonisolated let fileURL: URL
    private var loaded: [Line]?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            // "Browser" is the project's old name, kept: the files already on the phone are there.
            let support = URL.applicationSupportDirectory.appending(path: "Browser", directoryHint: .isDirectory)
            self.fileURL = support.appending(path: "lines.jsonl")
        }
    }

    public func all() -> [Line] { load() }
    public func loved() -> [Line] { load().filter { $0.source == .loved } }
    public func hated() -> [Line] { load().filter { $0.source == .hated } }

    public func add(_ line: Line) {
        var lines = load()
        lines.append(line)
        loaded = lines
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = try LineBook.encode(line)
            data.append(UInt8(ascii: "\n"))
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            // The line stays in memory for the launch; the file is the truth next time.
        }
    }

    public func clear() {
        loaded = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() -> [Line] {
        if let loaded { return loaded }
        let lines = (try? Data(contentsOf: fileURL)).flatMap { try? LineBook.parse($0) } ?? []
        loaded = lines
        return lines
    }
}

/// Which lines go with a request: the nearest in meaning, from a
/// `MeaningIndex` over the seed and the loved lines, keyed by line id. The
/// request's meaning is embedded once by the session, beside the route,
/// and handed in as a vector.
public actor LinePicker {
    private let index: MeaningIndex
    private var lines: [UUID: Line]
    private var caughtUp: Task<Void, Never>?

    public init(fileURL: URL, embedder: any Embedder, seed: [Line] = LineBook.seed(), loved: [Line] = []) {
        index = MeaningIndex(fileURL: fileURL, embedder: embedder)
        lines = Dictionary((seed + loved).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Every line not yet in the index, embedded, and every id the index
    /// holds for a line no longer in the book (a seed line rewritten) taken
    /// out; once per launch, before the first pick.
    public func catchUp() async {
        if caughtUp == nil {
            let items = lines.values.map { (id: $0.id, text: $0.indexText) }
            let known = Set(lines.keys)
            let index = index
            caughtUp = Task {
                let stale = await index.ids.subtracting(known)
                if !stale.isEmpty { await index.remove(stale) }
                await index.backfill(items)
            }
        }
        await caughtUp?.value
    }

    /// A loved line joins the book and the index.
    public func add(_ line: Line) async {
        lines[line.id] = line
        await index.index(line.id, text: line.indexText)
    }

    /// Lines kept from earlier launches join the book; the index catches
    /// up on them before the next pick.
    public func include(_ more: [Line]) {
        for line in more where lines[line.id] == nil { lines[line.id] = line }
        caughtUp = nil
    }

    public var count: Int { lines.count }

    /// The `limit` lines nearest the request's meaning. A line whose words
    /// are the request's own (`query`, case and punctuation aside) is left
    /// out: the book teaches the manner, never the answer to the same words.
    public func nearest(to vector: [Float], limit: Int = LineBook.limit, query: String? = nil) async -> [Line] {
        await catchUp()
        let key = query.map(Words.key)
        let found = await index.nearest(toVector: vector, limit: limit + 1).compactMap { lines[$0.id] }
        return Array(found.filter { key == nil || Words.key($0.user) != key }.prefix(limit))
    }

    public func flush() async { await index.flush() }
}
