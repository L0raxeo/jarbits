import Foundation

/// What `look` reads out of a thing that is not a web page: a note's lines,
/// an answer's text, numbered so a later look continues from a number and
/// a write names a line. A page is read by its own
/// script in the app; these are the device-side readers for everything
/// else, so nothing in the listing is more than one look away.
public enum Looking {
    /// Lines of a note shown at most per look.
    public static let noteLimit = 400
    /// Paragraphs of an answer shown at most per look.
    public static let paragraphLimit = 60

    public struct Read: Equatable, Sendable {
        /// The numbered text, or empty when there is nothing from `from` on.
        public var text: String
        /// The links in what was read, in order, for `s` handles.
        public var links: [ScreenItem]
        /// How many lines or paragraphs are left after the limit.
        public var more: Int

        public init(text: String, links: [ScreenItem] = [], more: Int = 0) {
            self.text = text
            self.links = links
            self.more = more
        }
    }

    /// A note's lines, `N| …`, links as their bracketed titles, from line
    /// `from` (1-based; nil or less than 1 is the top), `limit` at most.
    public static func lines(of note: Note, from: Int? = nil, limit: Int = noteLimit) -> Read {
        let body = note.body.trimmingCharacters(in: .newlines)
        let all = body.isEmpty ? [] : Note.linksBracketed(body).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let start = max((from ?? 1) - 1, 0)
        let shown = Array(all.dropFirst(start).prefix(limit))
        let text = shown.enumerated().map { "\(start + $0.offset + 1)| \($0.element)" }.joined(separator: "\n")
        let links = NoteMarkdown.links(in: NoteMarkdown.attributed(from: body)).map { ScreenItem(title: $0.title, address: $0.url) }
        return Read(text: text, links: links, more: max(all.count - start - shown.count, 0))
    }

    /// A note's headings with their line numbers, or a line saying it has none.
    public static func outline(of note: Note) -> String {
        let all = note.body.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let headings = all.enumerated().filter { NoteMarkdown.form(of: $0.element) == .heading }.map { "\($0.offset + 1)| \($0.element)" }
        return headings.isEmpty ? "no headings in my note \"\(note.title)\"" : headings.joined(separator: "\n")
    }

    /// An answer's text as numbered paragraphs (split at blank lines), from
    /// paragraph `from`, `limit` at most.
    public static func paragraphs(of text: String, from: Int? = nil, limit: Int = paragraphLimit) -> Read {
        let all = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let start = max((from ?? 1) - 1, 0)
        let shown = Array(all.dropFirst(start).prefix(limit))
        let numbered = shown.enumerated().map { "\(start + $0.offset + 1)| \($0.element)" }.joined(separator: "\n")
        return Read(text: numbered, links: [], more: max(all.count - start - shown.count, 0))
    }

    /// The line after a read that was cut: how to continue it.
    public static func moreLine(_ more: Int, unit: String) -> String? {
        more > 0 ? "… \(more) more \(unit) (from continues)" : nil
    }
}
