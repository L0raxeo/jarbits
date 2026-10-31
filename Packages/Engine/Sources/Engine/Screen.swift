import Foundation

/// What is on the screen at the moment a query starts, read once by the
/// device and put in front of every model that interprets: the reading
/// beside Jev, the planner and an answer about it. A web page gives its
/// visible text, the rest of its text, the selection, the links in view
/// and a picture of the viewport; a note its text; an answer its text; a
/// grid its tiles. Nothing here decides anything: the models read it,
/// under one rule (`rule`) about when the words lean on it.
public struct Screen: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case page, note, answer, grid, other
    }

    public var kind: Kind
    public var title: String
    public var address: URL?
    /// The text in the viewport, in full, up to `visibleLimit`.
    public var visible: String
    /// The page's text beyond the viewport, up to `restLimit`.
    public var rest: String
    /// The page had more text than `rest` holds: the block says so, so a
    /// plan knows a look reads on rather than guessing from the "…".
    public var restCut: Bool
    /// Text the user has selected, if any.
    public var selection: String?
    /// The links in view, in document order.
    public var items: [ScreenItem]
    /// The page's own data: what it publishes for search engines and link
    /// previews (canonical address, preview tags, structured blocks), as
    /// `key: value` lines in its own words, up to `dataLimit`. Web pages only.
    public var data: String
    /// A JPEG of the viewport, web pages only; nil when none could be taken.
    public var picture: Data?

    /// The visible text is kept whole up to this many characters.
    public static let visibleLimit = 4_000
    /// The rest of the page is kept up to this many.
    public static let restLimit = 8_000
    /// The most links listed as items.
    public static let itemLimit = 40
    /// The page's own data is kept up to this many characters.
    public static let dataLimit = 1_500

    public init(kind: Kind, title: String, address: URL? = nil, visible: String = "", rest: String = "", selection: String? = nil, items: [ScreenItem] = [], data: String = "", picture: Data? = nil) {
        self.kind = kind
        self.title = title
        self.address = address
        self.visible = Self.trimmed(visible, to: Self.visibleLimit)
        self.rest = Self.trimmed(rest, to: Self.restLimit)
        self.restCut = rest.count > Self.restLimit
        let selected = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.selection = selected.isEmpty ? nil : String(selected.prefix(Self.visibleLimit))
        self.items = Array(items.prefix(Self.itemLimit))
        self.data = Self.trimmed(data, to: Self.dataLimit)
        self.picture = picture
    }

    /// The one rule every model that sees the screen is given, the same
    /// words for the reader and the planner: when the words lean on it.
    public static let rule = "The screen is what the user sees now. Fold it in only where the words point at it: this, that one, the second, here, the one shown, the price on the page. A request that stands on its own, or leans on an earlier exchange, is left as it is."

    /// What the planner is told about the picture, beyond the rule.
    public static let pictureRule = "A picture of the screen comes with the request when there is one: what it shows that the text does not (a colour, a position, a chart, a layout) you read from the picture; anything on screen that the text or the listing names, you name by its handle."

    /// Whether anything beyond the title is known.
    public var isEmpty: Bool { visible.isEmpty && rest.isEmpty && selection == nil && items.isEmpty && data.isEmpty }

    /// One line naming what is on screen.
    public var described: String { described(handle: nil) }

    /// One line naming what is on screen, by its handle in the listing when
    /// it has one: "On screen, n1: my note "Trip"".
    public func described(handle: String?) -> String {
        let what: String = switch kind {
        case .page: "the page"
        case .note: "my note"
        case .answer: "the answer"
        case .grid: "a grid"
        case .other: "a card"
        }
        var line = "On screen\(handle.map { ", \($0)" } ?? ""): \(what) \"\(title)\""
        if let address { line += " at \(address.absoluteString)" }
        return line
    }

    /// The text block a model reads. The reader gets the selection and the
    /// visible text (`whole` false); the planner and an answer get the
    /// page's own data, the rest and the items too, each item by its handle when `handles` are given
    /// (the planner's), else by number. With `handle`, the thing on screen
    /// is named by it; a note or an answer so named is not repeated, since
    /// its content already stands in the listing under that handle.
    public func block(whole: Bool, handles: [String] = [], handle: String? = nil) -> String {
        if whole, let handle, kind == .note || kind == .answer {
            let under = kind == .note ? "its lines are listed under \(handle) above" : "listed under \(handle) above"
            var lines = ["\(described(handle: handle)) (\(under))"]
            if let selection { lines.append("Selected on it: \"\(selection)\"") }
            return lines.joined(separator: "\n")
        }
        var lines = [described(handle: handle)]
        if let selection { lines.append("Selected on it: \"\(selection)\"") }
        if !visible.isEmpty {
            lines.append(whole ? "Visible now:" : "Visible:")
            lines.append(visible)
        }
        guard whole else { return lines.joined(separator: "\n") }
        if !data.isEmpty {
            lines.append("The page's own data (what it publishes, not what it shows):")
            lines.append(data)
        }
        if !rest.isEmpty {
            lines.append(restCut ? "Further down the page (cut at \(Self.restLimit) characters; the page has more, which a look reads):" : "Further down the page:")
            lines.append(rest)
        }
        if !items.isEmpty {
            lines.append("Links in view, in order:")
            for (index, item) in items.enumerated() {
                let handle = handles.indices.contains(index) ? handles[index] : "\(index + 1)"
                lines.append("- \(handle): \(item.described)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func trimmed(_ text: String, to limit: Int) -> String {
        let clean = text.replacingOccurrences(of: "[ \\t\\x{00a0}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s*\\n\\s*", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        return String(clean.prefix(limit)) + "…"
    }
}

/// One link in view on a web page: a thing the planner can name by handle
/// (`s1, s2…`), with its text and its address. The device fills both;
/// no model carries or guesses an address.
public struct ScreenItem: Sendable, Equatable, Codable {
    public var title: String
    public var address: URL

    public init(title: String, address: URL) {
        self.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        self.address = address
    }

    /// The item as a listing line gives it: its text and where it goes.
    public var described: String {
        "\"\(title)\" \u{2192} \(address.absoluteString)"
    }
}
