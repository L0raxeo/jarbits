import Foundation

/// What Jarbits has done, as every model he asks is handed it: the record
/// as it stood when the request began, everything done for the request so
/// far with the whole of what was read, and the words of an answer still
/// coming out of him. One value, built by the session the moment a call is
/// made, required by every request builder, so no call can be made without
/// it. `ActionLog` is the lasting record; this is the request's view of it.
public struct Done: Sendable, Equatable {
    /// One thing done for this request: its line on the record, and the
    /// whole of what was read when the line is a read, kept for the request
    /// alone (the record keeps the line, cut).
    public struct Entry: Sendable, Equatable {
        public var record: ActionRecord
        public var full: String?

        public init(record: ActionRecord, full: String? = nil) {
            self.record = record
            self.full = full
        }
    }

    /// The newest of the record up to the request's start, oldest first.
    public var before: [ActionRecord]
    /// How many are older than `before`; the planner's `past` reads them.
    public var earlier: Int
    /// What was done for this request, oldest first.
    public var now: [Entry]
    /// The words of an answer still streaming, so far; nil when none is.
    public var saying: String?

    public init(before: [ActionRecord] = [], earlier: Int = 0, now: [Entry] = [], saying: String? = nil) {
        self.before = before
        self.earlier = earlier
        self.now = now
        self.saying = saying
    }

    /// Nothing known: a report or an eval that starts from nothing.
    public static let none = Done()

    /// The heading an answer reads it under, and the one the planner does.
    public static let answerHeading = "What you have done"
    public static let planHeading = "What I have done"

    /// Longer than this of a read's whole text is cut in the block.
    public static let maxFull = 2_000
    /// How many of the newest lines a reader gets.
    public static let briefCount = 4

    public var isEmpty: Bool { before.isEmpty && now.isEmpty && saying == nil }

    /// How a model reads the record: the one rule, in every prompt where he speaks.
    public static func rule(_ heading: String) -> String {
        "The block \"\(heading)\" is the full record of your own actions, written the moment each happened. A question about what you did, said, changed or showed is answered from it: what it lists, you did, and you own it plainly; what it does not list, you did not do. Never answer it from how something looks now, and never deny something it lists."
    }

    /// The block for a speaker, or nil when there is nothing: the record's
    /// lines, then this request's with what was read in full, then what he
    /// is saying. With nothing done for the request yet, exactly the block
    /// the listing had before requests kept their own memory, byte for byte.
    /// `past` says the planner's `past` tool reads what is earlier.
    public func block(heading: String, calendar: Calendar = .current, noteHandles: [UUID: String] = [:], past: Bool = false) -> String? {
        guard !isEmpty else { return nil }
        var lines = ["\(heading) (oldest first\(earlier > 0 && past ? "; \(earlier) earlier, which past reads" : "")):"]
        lines += before.map { "- " + $0.line(calendar: calendar, noteHandles: noteHandles) }
        if !now.isEmpty {
            lines.append("For this request, so far:")
            for entry in now {
                lines.append("- " + entry.record.line(calendar: calendar, noteHandles: noteHandles))
                if let full = entry.full?.trimmingCharacters(in: .whitespacesAndNewlines), !full.isEmpty, full != entry.record.what {
                    let cut = full.count > Self.maxFull ? String(full.prefix(Self.maxFull)) + "…" : full
                    lines += cut.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + String($0) }
                }
            }
        }
        if let saying = saying?.trimmingCharacters(in: .whitespacesAndNewlines), !saying.isEmpty {
            lines.append("Saying now, not finished: \(saying)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: A question about what he did

    /// The words that ask about his own actions, for when Jev did not say.
    static let didWords = ["did you", "have you", "did u", "what did you", "what have you", "you changed", "you change", "you delete", "you rewrote", "you wrote", "you said", "you read", "you touch", "undo", "put it back", "put that back", "take that back", "what did u"]

    /// Whether the query asks what he did, by its words alone.
    public static func asksWhatHeDid(_ query: String) -> Bool {
        let words = " " + query.lowercased().replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression) + " "
        return didWords.contains { words.contains(" " + $0 + " ") }
    }

    /// Whether the query points at the thing in view ("this", "it", "that",
    /// "the note", its title) rather than at something else he did.
    public static func pointsAtThingInView(_ query: String, title: String) -> Bool {
        let words = " " + query.lowercased().replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression) + " "
        if ["this", "it", "that", "these", "note", "notes", "list"].contains(where: { words.contains(" " + $0 + " ") }) { return true }
        let name = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && words.contains(name)
    }

    /// What to say about one note from its record alone, no model: the
    /// newest change he made to it, with when; or that he only showed it;
    /// or that he never touched it. `records` are the note's, oldest first.
    public static func say(aboutNote records: [ActionRecord], address: String? = "sir", calendar: Calendar = .current, now: Date = .now) -> String {
        let sir = address.map { ", \($0)" } ?? ""
        if let change = records.last(where: { $0.kind == .change }) {
            return "I did\(sir): \(change.when(calendar: calendar, now: now)) I \(change.what.prefix(1).lowercased() + change.what.dropFirst())."
        }
        if let shown = records.last(where: { $0.kind == .show }) {
            return "I haven't touched it\(sir). I only showed it to you, \(shown.when(calendar: calendar, now: now))."
        }
        return "I haven't touched it\(sir)."
    }

    /// The newest few lines for a reader, or nil with none: enough for
    /// "undo that" and "put it back" to resolve, never the whole record.
    public func brief(calendar: Calendar = .current) -> String? {
        let records = before + now.map(\.record)
        guard !records.isEmpty || saying != nil else { return nil }
        var lines = ["What I have just done (oldest first):"]
        lines += records.suffix(Self.briefCount).map { "- " + $0.line(calendar: calendar) }
        if let saying = saying?.trimmingCharacters(in: .whitespacesAndNewlines), !saying.isEmpty {
            lines.append("- Saying now, not finished: \(saying)")
        }
        return lines.joined(separator: "\n")
    }
}
