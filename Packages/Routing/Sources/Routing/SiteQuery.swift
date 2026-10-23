import Foundation

/// A request to open a website by name: "go to youtube", "pull up zillow",
/// "open insta", "can you take me to the airbnb site please". A template,
/// not understanding: leads and one opener come off the front, articles
/// after them, trailers off the end, and whatever is left is the name. The
/// name alone decides nothing; with an opener and a name the site book
/// knows, the app opens the site without asking a model (`LocalFirstRouter`),
/// and when Jev picks `site` the name is what gets looked up or searched.
public struct SiteQuery: Equatable, Sendable {
    /// The words left, lowercased and joined by single spaces; the book's key.
    public var name: String
    /// An opener was present ("go to", "open"); a bare name has none.
    public var hasOpener: Bool

    public init(name: String, hasOpener: Bool) {
        self.name = name
        self.hasOpener = hasOpener
    }

    /// Words that may come before the opener, any number of them. The
    /// one-word ones are what dictation puts in front: "Yo, pull up YouTube."
    public static let leads: [String] = [
        "can you", "could you", "would you", "all right", "please", "hey", "hi", "hello", "yo", "ok", "okay", "alright", "so", "um", "uh", "just",
    ]

    /// Phrases that ask for a site. Longer phrases first, so "open up" is
    /// tried before "open".
    public static let openers: [String] = [
        "take me to", "navigate to", "go to", "goto", "head to", "pull up", "bring up", "open up",
        "open", "launch", "load", "visit", "show me",
    ]

    /// Words that may sit between the opener and the name.
    public static let articles: [String] = ["the", "my"]

    /// Words that may close the query without changing it, any number of
    /// them: "the zillow website please" is zillow. Longer phrases first,
    /// so "home page" goes as one and not as "page" then a stranded "home".
    public static let trailers: [String] = [
        "home page", "web site", "dot com", "for me", "please", "now", "app", "website", "site", "page", "homepage", "com",
    ]

    public static func parse(_ query: String) -> SiteQuery? {
        var words = words(query)
        guard !words.isEmpty else { return nil }
        while strip(anyOf: leads, fromFrontOf: &words) {}
        let hasOpener = strip(anyOf: openers, fromFrontOf: &words)
        while strip(anyOf: articles, fromFrontOf: &words) {}
        while strip(anyOf: trailers, fromEndOf: &words) {}
        guard !words.isEmpty else { return nil }
        return SiteQuery(name: words.joined(separator: " "), hasOpener: hasOpener)
    }

    /// The name once the intent is settled: Jev has picked `site`, so the
    /// grammar's only job is to find the name, and the opener may sit
    /// anywhere ("what was it, um, open youtube"). The words after the first
    /// opener, articles and trailers gone; with no opener, the whole query
    /// as `parse` reads it. Never used to decide anything on its own: a
    /// loose match would open a site by mistake ("what happens when I open
    /// youtube").
    public static func name(in query: String) -> String? {
        let all = words(query)
        for start in all.indices {
            for opener in openers {
                let head = words(opener)
                let end = start + head.count
                guard end < all.count, Array(all[start..<end]) == head else { continue }
                var rest = Array(all[end...])
                while strip(anyOf: articles, fromFrontOf: &rest) {}
                while strip(anyOf: trailers, fromEndOf: &rest) {}
                if !rest.isEmpty { return rest.joined(separator: " ") }
            }
        }
        return parse(query)?.name
    }

    /// The name as the book keys it: the query's words with the articles and
    /// trailers gone, so "The Zillow website" and "zillow" are one entry.
    public static func key(_ name: String) -> String {
        var words = words(name)
        while strip(anyOf: articles, fromFrontOf: &words) {}
        while strip(anyOf: trailers, fromEndOf: &words) {}
        return words.joined(separator: " ")
    }

    /// Lowercased words with accents gone. Apostrophes vanish ("macy's" →
    /// "macys"); every other non-letter splits words, periods included, so
    /// "zillow.com" is "zillow" + "com" and the trailer rule drops the "com".
    public static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var words: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if scalar == "'" || scalar == "\u{2019}" {
                continue
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// Removes the first phrase of `phrases` found at the front, never the whole query.
    @discardableResult
    private static func strip(anyOf phrases: [String], fromFrontOf words: inout [String]) -> Bool {
        for phrase in phrases {
            let head = self.words(phrase)
            if words.count > head.count, Array(words.prefix(head.count)) == head {
                words.removeFirst(head.count)
                return true
            }
        }
        return false
    }

    /// Removes the first phrase of `phrases` found at the end, never the whole query.
    @discardableResult
    private static func strip(anyOf phrases: [String], fromEndOf words: inout [String]) -> Bool {
        for phrase in phrases {
            let tail = self.words(phrase)
            if words.count > tail.count, Array(words.suffix(tail.count)) == tail {
                words.removeLast(tail.count)
                return true
            }
        }
        return false
    }
}
