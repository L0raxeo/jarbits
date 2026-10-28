import Foundation
import Routing

/// The four levels of emphasis an answer may carry, top to bottom.
public enum Emphasis: Hashable, Sendable, CaseIterable {
    /// The one thing to take away; purple with white text. At most once per answer.
    case highlight
    /// A fact that directly answers the question.
    case bold
    /// A condition or caveat that changes the answer.
    case underline
    /// A name, title or term being introduced.
    case italic

    /// The marker the model writes on both sides of the text.
    public var marker: String {
        switch self {
        case .highlight: "=="
        case .bold: "**"
        case .underline: "__"
        case .italic: "_"
        }
    }
}

/// A run of answer text with the styles that apply to it.
public struct StyledSpan: Equatable, Sendable {
    public var text: String
    public var styles: Set<Emphasis>

    public init(_ text: String, styles: Set<Emphasis> = []) {
        self.text = text
        self.styles = styles
    }
}

/// The answer markup: four symmetric markers, not Markdown. The model is told
/// what each one means in `AnswerPrompt`; this turns its text into spans.
public enum AnswerMarkup {
    /// Which markers a format may use. One-line answers only highlight.
    public static func markers(for format: Instinct) -> [Emphasis] {
        switch format {
        case .oneLine: [.highlight]
        case .narrative: [.highlight, .bold, .underline, .italic]
        case .webResults, .map, .stock, .image, .video, .recall, .site, .remember, .forget, .time: []
        }
    }

    /// `text` as the card shows it: split on the markers the format allows, highlights padded.
    public static func styled(_ text: String, for format: Instinct) -> [StyledSpan] {
        paddingHighlights(spans(text, allowed: Set(markers(for: format))))
    }

    /// Splits `text` into spans. A marker toggles its style; styles nest. An
    /// opener with no closer styles to the end of the text, so a style shows
    /// as soon as its opener has streamed in. Markers not in `allowed` are
    /// left as literal text, as is a single underscore inside a word.
    public static func spans(_ text: String, allowed: Set<Emphasis>) -> [StyledSpan] {
        let chars = Array(text)
        var spans: [StyledSpan] = []
        var current = ""
        var active: Set<Emphasis> = []
        var i = 0

        func flush() {
            if !current.isEmpty {
                spans.append(StyledSpan(current, styles: active))
                current = ""
            }
        }

        while i < chars.count {
            if let style = marker(at: i, in: chars, allowed: allowed) {
                flush()
                if active.contains(style) { active.remove(style) } else { active.insert(style) }
                i += style.marker.count
            } else {
                current.append(chars[i])
                i += 1
            }
        }
        flush()
        return spans
    }

    /// Lets a highlight breathe. A run of highlighted spans with whitespace or
    /// nothing on both sides grows one space each way: a neighbouring plain
    /// space moves into the highlight, and a text edge, a newline or a space
    /// already taken by the previous highlight gets a no-break space instead.
    /// A highlight touching any other character, such as a comma, stays tight
    /// on both sides.
    public static func paddingHighlights(_ spans: [StyledSpan]) -> [StyledSpan] {
        var result = spans
        let pad: Character = "\u{00A0}"
        var i = 0
        var previousRegionEnd = -1   // index after the last region, to spot a shared space
        while i < result.count {
            guard result[i].styles.contains(.highlight) else { i += 1; continue }
            var end = i
            while end + 1 < result.count, result[end + 1].styles.contains(.highlight) { end += 1 }

            let before: Character? = i > 0 ? result[i - 1].text.last : nil
            let after: Character? = end + 1 < result.count ? result[end + 1].text.first : nil
            let emptyBefore = before.map(\.isWhitespace) ?? true
            let emptyAfter = after.map(\.isWhitespace) ?? true
            // A space the previous region already absorbed leaves its span empty;
            // `before` is then the highlighted space, which still counts as empty.
            guard emptyBefore && emptyAfter else { i = end + 1; continue }

            if before == " ", i - 1 >= previousRegionEnd, !result[i - 1].styles.contains(.highlight) {
                result[i - 1].text.removeLast()
                result[i].text.insert(" ", at: result[i].text.startIndex)
            } else {
                result[i].text.insert(pad, at: result[i].text.startIndex)
            }
            if after == " " {
                result[end + 1].text.removeFirst()
                result[end].text.append(" ")
            } else {
                result[end].text.append(pad)
            }
            previousRegionEnd = end + 1
            i = end + 1
        }
        return result.filter { !$0.text.isEmpty }
    }

    /// The text with every allowed marker removed.
    public static func plain(_ text: String, allowed: Set<Emphasis> = Set(Emphasis.allCases)) -> String {
        spans(text, allowed: allowed).map(\.text).joined()
    }

    /// Drops a trailing marker fragment, so a marker still streaming in never
    /// shows as a stray character. Only for text that is still arriving.
    public static func trimmingPartialMarker(_ text: String) -> String {
        var result = Substring(text)
        var dropped = 0
        while dropped < 2, let last = result.last, last == "=" || last == "*" || last == "_" {
            result = result.dropLast()
            dropped += 1
        }
        return String(result)
    }

    private static func marker(at i: Int, in chars: [Character], allowed: Set<Emphasis>) -> Emphasis? {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        switch (c, next) {
        case ("=", "="): return allowed.contains(.highlight) ? .highlight : nil
        case ("*", "*"): return allowed.contains(.bold) ? .bold : nil
        case ("_", "_"): return allowed.contains(.underline) ? .underline : nil
        case ("_", _):
            guard allowed.contains(.italic) else { return nil }
            // A single underscore counts only at a word boundary: `snake_case` stays.
            let previous: Character? = i > 0 ? chars[i - 1] : nil
            let insideWord = (previous?.isLetter ?? false) && (next?.isLetter ?? false)
            return insideWord ? nil : .italic
        default:
            return nil
        }
    }
}
