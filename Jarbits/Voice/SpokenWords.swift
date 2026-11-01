import Answers
import Foundation

/// The words a voice reads for a reply: what the bubble shows, with the
/// markup that shapes it on screen left out (emphasis markers, list
/// bullets, a link's address), and the sentences a streaming reply has
/// finished so far.
enum SpokenWords {
    /// The text as displayed, with nothing a voice would read as a symbol.
    static func from(_ text: String) -> String {
        let plain = AnswerMarkup.plain(text)
        let lines = plain.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var s = Substring(line).drop(while: { $0 == " " || $0 == "\t" })
            for marker in ["- [ ] ", "- [x] ", "- ", "* ", "• "] where s.hasPrefix(marker) {
                s = s.dropFirst(marker.count)
                break
            }
            if let dot = s.firstIndex(of: "."), s[s.startIndex..<dot].allSatisfy(\.isNumber), !s[s.startIndex..<dot].isEmpty, s.index(after: dot) < s.endIndex, s[s.index(after: dot)] == " " {
                s = s[s.index(dot, offsetBy: 2)...]
            }
            return String(s)
        }
        var joined = lines.joined(separator: "\n")
        joined = linksUnwrapped(joined)
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `[title](address)` → `title`.
    static func linksUnwrapped(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]*\)"#) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    /// The finished sentences of `text` past the first `from` characters,
    /// as one piece to send, with the count of characters of `text` they
    /// reach to; nil when none has finished. A sentence ends at a full
    /// stop, question or exclamation mark followed by a space or a line
    /// end, or at a line break.
    static func completeSentences(in text: String, from: Int) -> (piece: String, upTo: Int)? {
        guard from < text.count else { return nil }
        let rest = Array(text.dropFirst(from))
        var end = -1
        for i in rest.indices {
            let c = rest[i]
            if c == "\n" { end = i; continue }
            guard c == "." || c == "!" || c == "?" else { continue }
            if i + 1 < rest.count, rest[i + 1] == " " || rest[i + 1] == "\n" { end = i }
        }
        guard end >= 0 else { return nil }
        let piece = String(rest[0...end]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return nil }
        return (piece, from + end + 1)
    }
}
