import Foundation

/// One thing Jarbits did, in his own words, as it happened.
public struct ActionRecord: Codable, Sendable, Equatable {
    public var at: Date
    public var what: String
    /// The note it touched, so "did you change this?" finds it by the note,
    /// whatever the note is called now.
    public var noteID: UUID?
    /// The user's words it was for; nil for what he did on his own (a reminder going off).
    public var asked: String?

    public init(at: Date = .now, what: String, noteID: UUID? = nil, asked: String? = nil) {
        self.at = at
        self.what = what
        self.noteID = noteID
        self.asked = asked
    }

    /// One line of a model's context: when, what, and what it was for.
    public func line(calendar: Calendar = .current, noteHandles: [UUID: String] = [:]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE d MMM HH:mm"
        var line = "\(formatter.string(from: at)): \(what)"
        if let noteID, let handle = noteHandles[noteID] { line += " (\(handle))" }
        if let asked, !asked.isEmpty { line += " [for \"\(asked)\"]" }
        return line
    }
}

/// What Jarbits has done: every action, on the phone, for good. It is his
/// memory of himself, separate from the conversation (which ends after
/// twenty minutes of silence or a restart) and from the screen (which shows
/// only where things stand now). Each store writes here in the same step as
/// its change, and everything he shows or asks is written as it is shown, so
/// a request that is overtaken, a screen that moves on or an app that closes
/// loses nothing. Every planner request and every answer reads the newest of
/// it; the planner's `past` reads the rest. Only what he did goes here: what
/// the user does by hand does not. Calls are synchronous, so nothing he did
/// can be missing from the next thing he reads. Nothing in it leaves the
/// phone except inside a Gemini request, which keeps nothing.
public final class ActionLog: @unchecked Sendable {
    public static let shared = ActionLog()

    /// How many of the newest each request reads; the rest is one `past` away.
    public static let listed = 60
    /// Longer than this is cut: enough to know what it was, and an answer
    /// or a written passage can be read in full where it stands.
    public static let maxWhat = 400

    public let fileURL: URL
    private let lock = NSLock()
    private var loaded: [ActionRecord]?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "Browser", directoryHint: .isDirectory)
            .appending(path: "actions.jsonl")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Records it now, on disk before this returns.
    public func add(_ what: String, noteID: UUID? = nil, asked: String? = nil, at: Date = .now) {
        let trimmed = what.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let record = ActionRecord(at: at, what: Self.cut(trimmed), noteID: noteID, asked: asked.map(Self.cut))
        lock.lock()
        defer { lock.unlock() }
        var all = records()
        all.append(record)
        loaded = all
        write(record)
    }

    /// How many there are: a step that leaves this as it was recorded nothing.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return records().count
    }

    /// The newest `limit`, oldest first.
    public func newest(_ limit: Int = ActionLog.listed) -> [ActionRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(records().suffix(limit))
    }

    /// Those before the newest `skipping`, oldest first, and how many are
    /// earlier still; only the given note's when one is named.
    public func older(skipping: Int, limit: Int = ActionLog.listed, noteID: UUID? = nil) -> (records: [ActionRecord], earlier: Int) {
        lock.lock()
        defer { lock.unlock() }
        let all = records().filter { noteID == nil || $0.noteID == noteID }
        let end = max(all.count - skipping, 0)
        let start = max(end - limit, 0)
        return (Array(all[start..<end]), start)
    }

    /// Empties the file (a Debug clear of everything).
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        loaded = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func records() -> [ActionRecord] {
        if let loaded { return loaded }
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        // A line that cannot be read is skipped: the others still stand.
        let read = text.split(separator: "\n").compactMap { try? Self.decoder.decode(ActionRecord.self, from: Data($0.utf8)) }
        loaded = read
        return read
    }

    private func write(_ record: ActionRecord) {
        guard var line = try? Self.encoder.encode(record) else { return }
        line.append(UInt8(ascii: "\n"))
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                try Data().write(to: fileURL)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            print("ActionLog: \(error)")
        }
    }

    private static func cut(_ text: String) -> String {
        text.count > maxWhat ? String(text.prefix(maxWhat)) + "…" : text
    }
}

/// A rewrite said by what it did to the note's words, worked out by plain
/// comparison, so the record holds what really happened, not what was meant.
public enum ActionWords {
    public static func rewrote(title: String, from old: String, to new: String) -> String {
        let loss = NoteMarkdown.wordsLost(from: old, to: new)
        let added = NoteMarkdown.wordsLost(from: new, to: old).lost
        return "Rewrote my note \"\(title)\": took out \(loss.lost) of its \(loss.total) words and put in \(added)"
    }
}
