import Foundation

/// A note's body both ways: the Markdown on disk and the attributed text
/// the editor shows. Exactly six forms: bold, italic, a heading, a bullet,
/// a numbered item, a checkbox. Each paragraph carries its form in
/// `NoteParagraph`; bold and italic are the inline intents. Anything else
/// in a file is kept as plain text, so nothing is ever lost on the way.
public enum NoteParagraph: String, Codable, Sendable, Hashable {
    case plain
    case heading
    case bullet
    case numbered
    case checkbox
    case checked
}

public struct NoteParagraphAttribute: CodableAttributedStringKey {
    public typealias Value = NoteParagraph
    public static let name = "jarbits.note.paragraph"
}

extension AttributeScopes {
    public struct NoteAttributes: AttributeScope {
        public let paragraph: NoteParagraphAttribute
        public let foundation: FoundationAttributes
    }

    public var note: NoteAttributes.Type { NoteAttributes.self }
}

extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.NoteAttributes, T>) -> T { self[T.self] }
}

public enum NoteMarkdown {
    /// The editor's text from the file's body. Every line is a paragraph
    /// ending in a newline; its form is read from its marker and kept as
    /// the paragraph attribute; `**bold**` and `_italic_` become intents.
    public static func attributed(from markdown: String) -> AttributedString {
        var out = AttributedString()
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (index, line) in lines.enumerated() {
            let (form, rest) = split(line)
            var paragraph = inline(rest)
            paragraph[NoteParagraphAttribute.self] = form
            if index < lines.count - 1 {
                var newline = AttributedString("\n")
                newline[NoteParagraphAttribute.self] = form
                paragraph += newline
            }
            out += paragraph
        }
        return out
    }

    /// The file's body from the editor's text.
    public static func markdown(from attributed: AttributedString) -> String {
        var lines: [String] = []
        var number = 0
        for run in paragraphs(of: attributed) {
            let form = run.form
            let text = inlineMarkdown(run.text)
            switch form {
            case .plain: lines.append(text); number = 0
            case .heading: lines.append("## " + text); number = 0
            case .bullet: lines.append("- " + text); number = 0
            case .numbered: number += 1; lines.append("\(number). " + text)
            case .checkbox: lines.append("- [ ] " + text); number = 0
            case .checked: lines.append("- [x] " + text); number = 0
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Lines

    /// Text to add to a body, in the body's own form: when the body's last
    /// line is a bullet, a checkbox or a numbered item and the text's lines
    /// carry no marker of their own, each takes that marker (the next
    /// numbers for a numbered list), as a return at the end of a list does
    /// in Notes. Text that brings its own marks, or a body that is not a
    /// list, is added as it is.
    public static func continuing(_ text: String, after body: String) -> String {
        let last = body.split(separator: "\n").map(String.init).last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let last else { return text }
        let (form, _) = split(last)
        guard [.bullet, .checkbox, .checked, .numbered].contains(form) else { return text }
        var number = form == .numbered ? (Int(last.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }) ?? 0) : 0
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let line = String(line)
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, split(line).0 == .plain else { return line }
            switch form {
            case .numbered:
                number += 1
                return "\(number). " + line
            case .checkbox, .checked: return "- [ ] " + line
            default: return "- " + line
            }
        }.joined(separator: "\n")
    }

    /// `text` put into `body` after its line number `line` (as
    /// `Note.numberedLines` counts them): 0 puts it at the top, nil or a
    /// number past the last line puts it at the end. The model wrote the
    /// lines in the marks they should have; the device completes two things
    /// it may have left: bare words directly after a list item continue that
    /// list (`continuing`), and a numbered run the lines land in is counted
    /// again from 1 (`renumbered`).
    public static func insert(_ text: String, into body: String, after line: Int?) -> String {
        let body = body.trimmingCharacters(in: .newlines)
        var lines = body.isEmpty ? [] : body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let at = min(max(line ?? lines.count, 0), lines.count)
        let before = Array(lines.prefix(at))
        // The line directly before decides: after a blank line nothing is continued.
        let previous = before.last?.trimmingCharacters(in: .whitespaces).isEmpty == false ? before.joined(separator: "\n") : ""
        let text = continuing(text.trimmingCharacters(in: .newlines), after: previous)
        let added = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.insert(contentsOf: added, at: at)
        return renumbered(lines.joined(separator: "\n"))
    }

    /// Every contiguous run of numbered lines counted from 1 in order;
    /// nothing else is touched.
    public static func renumbered(_ body: String) -> String {
        var number = 0
        return body.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let line = String(line)
            guard let match = line.firstMatch(of: /^(\s*)(\d+)([.)] .*)$/) else { number = 0; return line }
            number += 1
            return "\(match.1)\(number)\(match.3)"
        }.joined(separator: "\n")
    }

    /// A line's form from its marker alone.
    public static func form(of line: String) -> NoteParagraph { split(line).0 }

    /// A line's form from its marker, and the text after it.
    static func split(_ line: String) -> (NoteParagraph, String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let rest = strip(trimmed, prefixes: ["- [ ] ", "* [ ] "]) { return (.checkbox, rest) }
        if let rest = strip(trimmed, prefixes: ["- [x] ", "- [X] ", "* [x] ", "* [X] "]) { return (.checked, rest) }
        if let rest = strip(trimmed, prefixes: ["- ", "* ", "+ "]) { return (.bullet, rest) }
        if let rest = strip(trimmed, prefixes: ["### ", "## ", "# "]) { return (.heading, rest) }
        if let match = trimmed.firstMatch(of: /^(\d+)[.)] (.*)$/) { return (.numbered, String(match.2)) }
        if trimmed == "- [ ]" || trimmed == "- [x]" { return (trimmed == "- [ ]" ? .checkbox : .checked, "") }
        if trimmed == "-" || trimmed == "*" { return (.bullet, "") }
        return (.plain, line)
    }

    private static func strip(_ line: String, prefixes: [String]) -> String? {
        for prefix in prefixes where line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
        return nil
    }

    // MARK: Inline

    /// `**bold**`, `__bold__`, `*italic*`, `_italic_`, `***both***`, and a
    /// link `[title](url)`, which becomes its title carrying the address.
    static func inline(_ text: String) -> AttributedString {
        var out = AttributedString()
        var rest = Substring(text)
        while !rest.isEmpty {
            if let link = rest.firstMatch(of: /\[([^\]]+)\]\(([^)\s]+)\)/), let url = URL(string: String(link.2)),
               rest.firstMatch(of: /(\*\*\*|___)(.+?)\1|(\*\*|__)(.+?)\3|(\*|_)(.+?)\5/).map({ link.range.lowerBound <= $0.range.lowerBound }) ?? true {
                out += AttributedString(String(rest[rest.startIndex..<link.range.lowerBound]))
                var piece = AttributedString(String(link.1))
                piece.link = url
                out += piece
                rest = rest[link.range.upperBound...]
                continue
            }
            if let match = rest.firstMatch(of: /(\*\*\*|___)(.+?)\1|(\*\*|__)(.+?)\3|(\*|_)(.+?)\5/) {
                out += AttributedString(String(rest[rest.startIndex..<match.range.lowerBound]))
                var piece: AttributedString
                if let both = match.2 {
                    piece = AttributedString(String(both))
                    piece.inlinePresentationIntent = [.stronglyEmphasized, .emphasized]
                } else if let bold = match.4 {
                    piece = AttributedString(String(bold))
                    piece.inlinePresentationIntent = .stronglyEmphasized
                } else {
                    piece = AttributedString(String(match.6 ?? ""))
                    piece.inlinePresentationIntent = .emphasized
                }
                out += piece
                rest = rest[match.range.upperBound...]
            } else {
                out += AttributedString(String(rest))
                break
            }
        }
        return out
    }

    static func inlineMarkdown(_ text: AttributedString) -> String {
        var out = ""
        for run in text.runs {
            let piece = String(text[run.range].characters)
            if let url = run.link {
                out += "[\(piece)](\(url.absoluteString))"
                continue
            }
            let intent = run.inlinePresentationIntent ?? []
            let bold = intent.contains(.stronglyEmphasized)
            let italic = intent.contains(.emphasized)
            switch (bold, italic) {
            case (true, true): out += "***" + piece + "***"
            case (true, false): out += "**" + piece + "**"
            case (false, true): out += "_" + piece + "_"
            case (false, false): out += piece
            }
        }
        return out
    }

    /// Every link in the text, in order: its title and address.
    public static func links(in attributed: AttributedString) -> [(title: String, url: URL)] {
        attributed.runs.compactMap { run in
            run.link.map { (String(attributed[run.range].characters), $0) }
        }
    }

    // MARK: Paragraphs

    public struct Paragraph: Sendable {
        public var form: NoteParagraph
        public var text: AttributedString

        public init(form: NoteParagraph, text: AttributedString) {
            self.form = form
            self.text = text
        }
    }

    /// The text cut at newlines; a paragraph's form is the attribute on its
    /// first character, plain when it has none.
    public static func paragraphs(of attributed: AttributedString) -> [Paragraph] {
        var out: [Paragraph] = []
        var current = AttributedString()
        var form: NoteParagraph?
        for run in attributed.runs {
            let piece = attributed[run.range]
            let runForm = run[NoteParagraphAttribute.self]
            var pending = AttributedString(piece)
            while let newline = pending.characters.firstIndex(of: "\n") {
                current += AttributedString(pending[pending.startIndex..<newline])
                out.append(Paragraph(form: form ?? runForm ?? .plain, text: current))
                current = AttributedString()
                form = nil
                pending = AttributedString(pending[pending.index(afterCharacter: newline)...])
            }
            if form == nil, !pending.characters.isEmpty { form = runForm }
            current += pending
        }
        out.append(Paragraph(form: form ?? .plain, text: current))
        return out
    }
}
