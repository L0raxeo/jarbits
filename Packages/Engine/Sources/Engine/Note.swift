import Foundation

/// One note in Jarbits's notebook: a Markdown file on the device, permanent,
/// not a memory. The first line is `# Title`, then a blank line, then the
/// body in the six forms `NoteMarkdown` knows. The dates are the file's.
public struct Note: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    /// The body in Markdown, without the title line.
    public var body: String
    public var created: Date
    public var edited: Date

    public init(id: UUID = UUID(), title: String, body: String = "", created: Date = .now, edited: Date? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.created = created
        self.edited = edited ?? created
    }

    /// The file's text: the title line, a blank line, the body.
    public var markdown: String {
        "# \(title)\n\n\(body)"
    }

    /// A file's text read back: the first `# ` line is the title; a file
    /// with no title line is titled by its first words.
    public static func parse(_ markdown: String, id: UUID, created: Date, edited: Date) -> Note {
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var title = ""
        if let first = lines.first, first.hasPrefix("# ") {
            title = String(first.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.removeFirst()
            if lines.first?.isEmpty == true { lines.removeFirst() }
        }
        let body = lines.joined(separator: "\n")
        if title.isEmpty { title = Self.title(from: body) }
        return Note(id: id, title: title, body: body, created: created, edited: edited)
    }

    /// A title from a body's first words, for a note made without one.
    public static func title(from text: String) -> String {
        let first = text.split(separator: "\n").map(String.init).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let plain = first.replacingOccurrences(of: "^[#>\\-*\\d.\\s\\[\\]x]+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let words = plain.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "Untitled" : words
    }

    /// The first lines of the body, plain, for a tile or a listing: a
    /// link shows as its title, bold and italic as their words.
    public var excerpt: String {
        let plain = Self.plain(body)
        return plain.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(3).joined(separator: " ").prefix(160).description
    }

    /// The first lines as written, marks and all, links as their titles:
    /// what the planner's listing shows, so it sees a list as a list and
    /// adds to it in kind.
    public var preview: String {
        Self.linksAsTitles(body)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(3).joined(separator: " / ").prefix(160).description
    }

    /// The most lines, and the most characters, of a note the planner's
    /// listing shows; a longer note is cut with a line saying how much more.
    /// Wide enough that a note the planner is asked to rewrite is shown
    /// whole (60 lines and 3,000 characters cut real notes; 2026-10-31).
    public static let linesListed = 200
    public static let charactersListed = 12_000

    /// The whole body as the planner's listing shows it: every line as
    /// written, marks and all, numbered from 1 so a write can name the line
    /// it goes after; a link as its title in square brackets, so the
    /// planner sees which lines are links without ever seeing an address;
    /// empty lines kept, since they are places too. Capped by
    /// `linesListed` and `charactersListed`.
    public var numberedLines: [String] {
        let lines = Self.linksBracketed(body.trimmingCharacters(in: .newlines)).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty, lines != [""] else { return [] }
        var out: [String] = []
        var characters = 0
        for (index, line) in lines.enumerated() {
            if out.count >= Self.linesListed || characters + line.count > Self.charactersListed {
                out.append("\u{2026} \(lines.count - index) more lines (too long to rewrite whole: add or remove by line)")
                break
            }
            out.append("\(index + 1)| \(line)")
            characters += line.count
        }
        return out
    }

    /// Links as their titles: the model reads what a line is, not its address.
    static func linksAsTitles(_ markdown: String) -> String {
        markdown.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
    }

    /// Links as their titles in square brackets, the address gone: a line
    /// the planner can tell is a link, in a form it copies back whole.
    static func linksBracketed(_ markdown: String) -> String {
        markdown.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "[$1]", options: .regularExpression)
    }

    /// What the meaning index keeps for the note: the title, then the
    /// body's first words, plain.
    public var indexText: String {
        let words = Self.plain(body).split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
        return ([title] + (words.isEmpty ? [] : [String(words.prefix(400))])).joined(separator: "\n")
    }

    /// Markdown's marks taken out: links to their titles, bold and italic
    /// to their words.
    static func plain(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    /// The words of the title and body, for a search.
    var haystack: String { title + "\n" + body }
}

/// The notes a query may mean. With `ranked`, the ids of the notes nearest
/// the request in meaning (the meaning index's order), those come first,
/// taking turns with the word matches, so a note the words name and a
/// note the meaning finds both make the list. Without it, the topic's
/// words in their titles and text (a title match first), newest edited
/// first among equals; with no topic, the newest. The same word matching
/// as the memories'.
public enum NoteSearch {
    public static let limit = 10

    public static func shortlist(_ notes: [Note], topic: String?, limit: Int = limit, ranked: [UUID] = []) -> [Note] {
        let words = byWords(notes, topic: topic, limit: limit)
        guard !ranked.isEmpty else { return words }
        let byID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let near = ranked.compactMap { byID[$0] }
        return MemorySearch.interleave(near, words, limit: limit)
    }

    static func byWords(_ notes: [Note], topic: String?, limit: Int) -> [Note] {
        let terms = MemorySearch.terms(of: topic)
        let newest = notes.sorted { $0.edited > $1.edited }
        guard !terms.isEmpty else { return Array(newest.prefix(limit)) }
        let scored = newest.compactMap { note -> (note: Note, hits: Int, inTitle: Bool)? in
            let titleWords = Set(MemorySearch.tokens(of: note.title))
            let words = Set(MemorySearch.tokens(of: note.haystack))
            let hits = terms.filter { term in words.contains { MemorySearch.close(term, $0) } }.count
            let inTitle = terms.contains { term in titleWords.contains { MemorySearch.close(term, $0) } }
            return hits > 0 ? (note, hits, inTitle) : nil
        }
        return scored
            .sorted {
                if $0.inTitle != $1.inTitle { return $0.inTitle }
                if $0.hits != $1.hits { return $0.hits > $1.hits }
                return $0.note.edited > $1.note.edited
            }
            .prefix(limit)
            .map(\.note)
    }
}

/// The pure parts of judging which note a query means: one yes/no per
/// candidate in a single request, the fact judge's shape. `NoteResolver`
/// sends it. On no path in the app since the meaning index: the planner
/// chooses from the nearest notes and names one by handle, and nothing
/// re-judges its choice. Kept for the CLI and as the shape of a judge.
public enum NoteRouting {
    /// At or above this, a note is the one meant: alone, it is acted on.
    public static let noteThreshold = 0.5
    /// Below that but at or above this, a note is plausible: offered among the choices.
    public static let maybeThreshold = 0.3

    public static let noteCriteria = (
        yes: "The query means this note: by its title, what it is about, what it holds, or when it was written or last edited.",
        no: "A different note, even on a nearby subject or sharing a word with the query."
    )

    public static func questionID(_ index: Int) -> String { "n\(index)" }

    public static func request(for query: String, candidates: [Note], now: Date, locale: Locale = .current, model: String = JevClient.defaultModel, calendar: Calendar = .current) -> SystemOneRequest {
        SystemOneRequest(
            model: model,
            state: RouteState(query: query, locale: locale.identifier),
            questions: candidates.enumerated().map { index, note in
                (questionID(index), .noul(instructions: instructions(for: note, now: now, calendar: calendar), criteria: noteCriteria))
            }
        )
    }

    public static func instructions(for note: Note, now: Date, calendar: Calendar = .current) -> String {
        var line = "Is this the note the query means? \"\(note.title)\", edited \(RecallRouting.when(note.edited, now: now, calendar: calendar))."
        let excerpt = note.excerpt
        if !excerpt.isEmpty { line += " It begins: \"\(String(excerpt.prefix(120)))\"." }
        return line
    }

    public static func picks(from response: SystemOneResponse, candidates: [Note], threshold: Double = maybeThreshold) -> [NotePick] {
        candidates.enumerated().compactMap { index, note -> NotePick? in
            guard case let .noul(probability)? = response.answers[questionID(index)], probability >= threshold else { return nil }
            return NotePick(note: note, probability: probability)
        }
        .sorted { $0.probability > $1.probability }
    }
}

public struct NotePick: Equatable, Sendable {
    public var note: Note
    public var probability: Double

    public init(note: Note, probability: Double) {
        self.note = note
        self.probability = probability
    }
}

public enum NoteVerdict: Equatable, Sendable {
    case picked([NotePick], latencyMs: Int)
    case failed(String)
}

/// Sends a note shortlist to Jev and reads the picks. Never throws.
public struct NoteResolver: Sendable {
    public var client: JevClient
    public var locale: Locale

    public init(client: JevClient, locale: Locale = .current) {
        self.client = client
        self.locale = locale
    }

    public func resolve(_ query: String, candidates: [Note], now: Date = .now, threshold: Double = NoteRouting.maybeThreshold) async -> NoteVerdict {
        guard !candidates.isEmpty else { return .picked([], latencyMs: 0) }
        let request = NoteRouting.request(for: query, candidates: candidates, now: now, locale: locale, model: client.model)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let response = try await client.systemOne(request)
            return .picked(NoteRouting.picks(from: response, candidates: candidates, threshold: threshold), latencyMs: Int((clock.now - start) / .milliseconds(1)))
        } catch {
            return .failed(error.summary)
        }
    }
}
