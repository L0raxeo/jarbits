import Foundation

/// A question that only wants the time somewhere: "what time is it in
/// Tokyo?", "current time in Mexico", or the bare "what time is it". It is a
/// template, not understanding: the query must start with one of the openers
/// and end with the place (or with nothing, for the bare forms), with at most
/// one of the trailers at the end. Anything else, such as "what time is the
/// game in Mexico", is not a time query and goes to the models.
public struct TimeQuery: Equatable, Sendable {
    /// The words after the opener, normalised; nil for the bare forms, which
    /// mean the user's own zone.
    public var place: String?

    public init(place: String?) {
        self.place = place
    }

    /// Phrases that introduce a place. Longer phrases first, so "what time
    /// is it in" is tried before "time in".
    public static let placeOpeners: [String] = [
        "what time is it in", "what's the time in", "what is the time in", "what time is in", "what time in",
        "current time in", "local time in", "the time in", "time now in", "time in",
    ]

    /// Whole queries that ask for the time here.
    public static let bareOpeners: [String] = [
        "what time is it", "what's the time", "what is the time", "current time", "local time", "the time", "time now",
    ]

    /// Words that may close either form without changing it, and may also sit
    /// between "is it" and "in" ("what time is it now in Tokyo").
    public static let trailers: [String] = ["at the moment", "right now", "currently", "now", "today"]

    public static func parse(_ query: String) -> TimeQuery? {
        var words = normalized(query)
        guard !words.isEmpty else { return nil }
        if isBare(words) { return TimeQuery(place: nil) }   // before the strip: "time now" is a bare opener, not "time" + a trailer
        stripTrailer(&words)
        if isBare(words) { return TimeQuery(place: nil) }
        for opener in placeOpeners {
            let head = normalized(opener)
            if let place = remainder(after: head, in: words) {
                return TimeQuery(place: place)
            }
            guard head.last == "in" else { continue }
            for trailer in trailers {
                let variant = Array(head.dropLast()) + normalized(trailer) + ["in"]
                if let place = remainder(after: variant, in: words) {
                    return TimeQuery(place: place)
                }
            }
        }
        return nil
    }

    /// Lowercased words with accents and punctuation gone, so "What's the
    /// time in São Paulo?" and "whats the time in sao paulo" are the same
    /// words. Apostrophes and periods vanish ("St. John's" → "st johns",
    /// "L.A." → "la"); hyphens, slashes and ampersands split words
    /// ("Port-au-Prince" → "port au prince"); "saint" becomes "st", the
    /// spelling the zone database uses.
    public static func normalized(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var words: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if scalar == "'" || scalar == "\u{2019}" || scalar == "." {
                continue
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0 == "saint" ? "st" : $0 }
    }

    private static func isBare(_ words: [String]) -> Bool {
        bareOpeners.contains { normalized($0) == words }
    }

    private static func remainder(after head: [String], in words: [String]) -> String? {
        guard words.count > head.count, Array(words.prefix(head.count)) == head else { return nil }
        return words.dropFirst(head.count).joined(separator: " ")
    }

    /// Drops one trailer from the end, never the whole query.
    private static func stripTrailer(_ words: inout [String]) {
        for trailer in trailers {
            let tail = normalized(trailer)
            if words.count > tail.count, Array(words.suffix(tail.count)) == tail {
                words.removeLast(tail.count)
                return
            }
        }
    }
}
