import Foundation

/// The pure parts of judging which fact a query asks the app to forget:
/// one yes/no question per candidate in a single request, and the picks
/// read back. The recall judge's pattern over facts. No I/O here;
/// `FactResolver` sends it.
public enum FactRouting {
    /// At or above this, a fact is the one asked for: alone, it is put to
    /// the user to confirm.
    public static let forgetThreshold = 0.5

    /// Below `forgetThreshold` but at or above this, a fact is plausible:
    /// offered among the choices, never dropped unasked.
    public static let maybeThreshold = 0.3

    public static let forgetCriteria = (
        yes: "The query asks to forget, drop, undo or correct this fact: by its words, its subject, or as the thing just remembered.",
        no: "A different fact, even on a nearby subject; or the query asks to forget a page, a search or an answer, which is not a fact."
    )

    public static func questionID(_ index: Int) -> String { "f\(index)" }

    public static func request(
        for query: String,
        candidates: [Fact],
        now: Date,
        locale: Locale = .current,
        model: String = JevClient.defaultModel,
        calendar: Calendar = .current
    ) -> SystemOneRequest {
        SystemOneRequest(
            model: model,
            state: RouteState(query: query, locale: locale.identifier),
            questions: candidates.enumerated().map { index, fact in
                (questionID(index), .noul(instructions: instructions(for: fact, now: now, calendar: calendar), criteria: forgetCriteria))
            }
        )
    }

    /// One candidate, as Jev reads it: its words, how it came to be known, and when.
    public static func instructions(for fact: Fact, now: Date, calendar: Calendar = .current) -> String {
        "Is this the fact the query asks the app to forget? \"\(fact.text)\", \(describe(fact.source)) \(RecallRouting.when(fact.date, now: now, calendar: calendar))."
    }

    static func describe(_ source: Fact.Source) -> String {
        switch source {
        case .told: "told to the app"
        case .chosen: "chosen by the user"
        case .inferred: "noted from what the user said"
        }
    }

    /// The candidates at or above `threshold`, surest first. A missing answer is a no.
    public static func picks(from response: SystemOneResponse, candidates: [Fact], threshold: Double = maybeThreshold) -> [FactPick] {
        candidates.enumerated().compactMap { index, fact -> FactPick? in
            guard case let .noul(probability)? = response.answers[questionID(index)], probability >= threshold else { return nil }
            return FactPick(fact: fact, probability: probability)
        }
        .sorted { $0.probability > $1.probability }
    }
}

public struct FactPick: Equatable, Sendable {
    public var fact: Fact
    public var probability: Double

    public init(fact: Fact, probability: Double) {
        self.fact = fact
        self.probability = probability
    }
}

public enum FactVerdict: Equatable, Sendable {
    /// Jev answered; the picks may be empty, which means none of them.
    case picked([FactPick], latencyMs: Int)
    /// The request failed; the app offers the shortlist in word order instead.
    case failed(String)
}

/// Sends a fact shortlist to Jev and reads the picks. Never throws.
public struct FactResolver: Sendable {
    public var client: JevClient
    public var locale: Locale

    public init(client: JevClient, locale: Locale = .current) {
        self.client = client
        self.locale = locale
    }

    public func resolve(_ query: String, candidates: [Fact], now: Date = .now, threshold: Double = FactRouting.maybeThreshold) async -> FactVerdict {
        guard !candidates.isEmpty else { return .picked([], latencyMs: 0) }
        let request = FactRouting.request(for: query, candidates: candidates, now: now, locale: locale, model: client.model)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let response = try await client.systemOne(request)
            let latency = Int((clock.now - start) / .milliseconds(1))
            return .picked(FactRouting.picks(from: response, candidates: candidates, threshold: threshold), latencyMs: latency)
        } catch {
            return .failed(error.summary)
        }
    }
}
