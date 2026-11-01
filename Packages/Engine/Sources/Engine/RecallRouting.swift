import Foundation

/// The pure parts of judging a recall shortlist with Jev: one yes/no
/// question per candidate in a single request, and the picks read back.
/// No I/O here; `RecallResolver` sends it.
public enum RecallRouting {
    /// At or above this, a webpage is the one asked for: alone, it comes forward.
    public static let recallThreshold = 0.5

    /// Below `recallThreshold` but at or above this, a webpage is plausible:
    /// shown in the grid for the user to choose, never brought forward unasked.
    public static let maybeThreshold = 0.3

    public static let recallCriteria = (
        yes: "The query describes this webpage: by what it is, when it was opened, what it is about, or a word of its title.",
        no: "A different thing, even if it shares a word with the query or is of the same kind."
    )

    /// At or above this, a webpage belongs to a collection ("everything
    /// about the dyson"): every one that does is shown, newest first.
    public static let collectionThreshold = 0.5

    public static let collectionCriteria = (
        yes: "This webpage is about the thing, topic or name the query asks for everything about: its title, its query or its address concerns it, whatever kind of webpage it is.",
        no: "About something else, even of the same kind, from the same day, or sharing an unrelated word with the query."
    )

    public static func questionID(_ index: Int) -> String { "m\(index)" }

    /// `collection` asks, per webpage, whether it is about the topic rather
    /// than whether it is the one thing asked for.
    public static func request(
        for query: String,
        candidates: [Webpage],
        now: Date,
        locale: Locale = .current,
        model: String = JevClient.defaultModel,
        calendar: Calendar = .current,
        collection: Bool = false
    ) -> SystemOneRequest {
        SystemOneRequest(
            model: model,
            state: RouteState(query: query, locale: locale.identifier),
            questions: candidates.enumerated().map { index, webpage in
                (questionID(index), .noul(
                    instructions: instructions(for: webpage, now: now, calendar: calendar, collection: collection),
                    criteria: collection ? collectionCriteria : recallCriteria
                ))
            }
        )
    }

    /// One candidate, as Jev reads it: its kind, since when it has been
    /// open, its host for a page, and its title.
    public static func instructions(for webpage: Webpage, now: Date, calendar: Calendar = .current, collection: Bool = false) -> String {
        var line = collection ? "Is this webpage about what the query asks for everything about?" : "Is this the webpage the query asks for?"
        line += " A \(describe(webpage.kind)) open since \(when(webpage.opened, now: now, calendar: calendar))"
        if webpage.kind == .page, let host = webpage.address.host() { line += " (\(host))" }
        line += ": \"\(webpage.title)\"."
        return line
    }

    static func describe(_ kind: Webpage.Kind) -> String {
        switch kind {
        case .page: "web page"
        case .search: "search"
        case .images: "picture search"
        }
    }

    /// "today", "yesterday", "3 days ago", or the date for anything older.
    public static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        case 2...6: return "\(days) days ago"
        default:
            var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            style.locale = Locale(identifier: "en_US")
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return "on " + date.formatted(style)
        }
    }

    /// The candidates at or above `threshold`, surest first. A missing answer is a no.
    public static func picks(from response: SystemOneResponse, candidates: [Webpage], threshold: Double = maybeThreshold) -> [RecallPick] {
        candidates.enumerated().compactMap { index, webpage -> RecallPick? in
            guard case let .noul(probability)? = response.answers[questionID(index)], probability >= threshold else { return nil }
            return RecallPick(webpage: webpage, probability: probability)
        }
        .sorted { $0.probability > $1.probability }
    }
}

public struct RecallPick: Equatable, Sendable {
    public var webpage: Webpage
    public var probability: Double

    public init(webpage: Webpage, probability: Double) {
        self.webpage = webpage
        self.probability = probability
    }
}

public enum RecallVerdict: Equatable, Sendable {
    /// Jev answered; the picks may be empty, which means none of them.
    case picked([RecallPick], latencyMs: Int)
    /// The request failed; the app shows the shortlist in word order instead.
    case failed(String)
}

/// Sends a recall shortlist to Jev and reads the picks. Never throws.
public struct RecallResolver: Sendable {
    public var client: JevClient
    public var locale: Locale

    public init(client: JevClient, locale: Locale = .current) {
        self.client = client
        self.locale = locale
    }

    /// `collection` asks the "about" question and keeps every webpage at or
    /// above the collection threshold.
    public func resolve(_ query: String, candidates: [Webpage], now: Date = .now, threshold: Double? = nil, collection: Bool = false) async -> RecallVerdict {
        guard !candidates.isEmpty else { return .picked([], latencyMs: 0) }
        let threshold = threshold ?? (collection ? RecallRouting.collectionThreshold : RecallRouting.maybeThreshold)
        let request = RecallRouting.request(for: query, candidates: candidates, now: now, locale: locale, model: client.model, collection: collection)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let response = try await client.systemOne(request)
            let latency = Int((clock.now - start) / .milliseconds(1))
            return .picked(RecallRouting.picks(from: response, candidates: candidates, threshold: threshold), latencyMs: latency)
        } catch {
            return .failed(error.summary)
        }
    }
}

extension JevError {
    /// The error in a few words, for the log.
    public var summary: String {
        switch self {
        case .timeout: "timeout"
        case let .transport(message): "transport: \(message)"
        case let .http(status, body): "http \(status): \(body)"
        case let .decoding(message): "decoding: \(message)"
        }
    }
}
