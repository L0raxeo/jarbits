import Foundation

/// Which facts a query's answer and plan see. Every fact used to go into
/// every answer and every plan, "since there are few"; a year of use makes
/// hundreds, and a thousand facts drowned the one that mattered in the
/// tests of 2026-11-02 ("what month do I graduate?" with the Lehigh fact
/// among a thousand: never answered; among the picked few: always). So Jev
/// scores each fact against the query, in a request of its own beside the
/// main pick, and only the facts that could matter go. The pure parts live
/// here: the request, the scores read back, the selection. `FactPicker`
/// sends it; the session waits a bounded moment for it and falls back to
/// every fact, as before, when Jev is slow or down. The fact reader, which
/// decides what a query states, still sees every fact.
public enum FactPicking {
    /// This request alone runs on 1.14: it scored the needed facts higher
    /// and the traps lower than 1.13 in the tests. The main pick stays on
    /// `JevClient.defaultModel`.
    public static let model = "jev-1.14.0"

    /// A fact goes when one minus the probability of "not at all" is at
    /// least this. At a thousand facts, 48 of 48 needed facts passed it and
    /// about twenty facts went on average before the cap.
    public static let threshold = 0.3

    /// The highest-scoring facts past the threshold, at most this many.
    public static let maxSent = 30

    /// Facts per request. Six hundred in one request went over Jev's 64k
    /// token limit; 400 answered in about 0.4 s on the Mac and leaves room
    /// for the exchanges. More facts mean more requests, sent at once.
    public static let chunk = 400

    /// The newest exchanges sent in the state, so "and what's she into"
    /// after "how old is my mom" scores the mother's facts. The same count
    /// the fact reader gets (`FactReader.exchangesGiven`; a test keeps them equal).
    public static let exchangesGiven = 5

    /// An exchange's text is cut to this many characters in this request
    /// only: a long answer must not push a full chunk over the token limit.
    public static let exchangeChars = 300

    /// How long the session waits for the pick once the route has landed
    /// before every fact goes instead. The pick normally finishes while
    /// the reading (about a second) is still running, so this rarely
    /// counts; measured on the phone and tuned from the log.
    public static let wait: Duration = .milliseconds(1500)

    /// The planner's `facts` tool has a plan's time: it waits this long.
    public static let lookupWait: Duration = .seconds(8)

    /// The client's own limit per request.
    public static let timeout: Duration = .seconds(3)

    /// Facts noted in the conversation still going (the ones `Fact.line`
    /// marks "just noted") always go, whatever their score, so "that's not
    /// true" straight after a fact lands has the fact in view.
    public static let alwaysWithin: TimeInterval = ConversationMemory.silence

    public static let question = "How much could this fact about the user matter to answering the query?"

    /// The scale, low to high. The score used is one minus the first
    /// level's probability: how far Jev is from "not at all".
    public static let levels = [
        "Not at all: a good answer would be exactly the same without it.",
        "Slightly or indirectly: it could change or help the answer.",
        "Directly: the answer needs it.",
    ]

    public static func questionID(_ index: Int) -> String { "f\(index)" }

    public static func instructions(for fact: Fact) -> String {
        "\(question) \"\(fact.text)\""
    }

    /// The state: the query, the locale and the newest `exchangesGiven`
    /// exchanges as Jev is sent them, each text cut to `exchangeChars`.
    public static func state(query: String, exchanges: [Exchange], locale: Locale) -> RouteState {
        let sent = exchanges.suffix(exchangesGiven).map { exchange -> Exchange in
            var copy = exchange.forJev
            if let text = copy.text, text.count > exchangeChars {
                copy.text = String(text.prefix(exchangeChars)) + "…"
            }
            return copy
        }
        return RouteState(query: query, locale: locale.identifier, exchanges: sent.isEmpty ? nil : Array(sent))
    }

    /// One request: one score question per fact, ids `f0…`, in the order given.
    public static func request(for query: String, facts: [Fact], exchanges: [Exchange] = [], locale: Locale = .current, model: String = model) -> SystemOneRequest {
        SystemOneRequest(
            model: model,
            state: state(query: query, exchanges: exchanges, locale: locale),
            questions: facts.enumerated().map { index, fact in
                (questionID(index), .score(instructions: instructions(for: fact), levels: levels))
            }
        )
    }

    /// The facts in requests of `size`, order kept.
    public static func chunks(_ facts: [Fact], size: Int = chunk) -> [[Fact]] {
        guard !facts.isEmpty, size > 0 else { return [] }
        return stride(from: 0, to: facts.count, by: size).map { Array(facts[$0..<min($0 + size, facts.count)]) }
    }

    /// Each fact's score from the answers, in the order sent: one minus the
    /// probability of "not at all". A missing or differently typed answer
    /// scores 0, never a guess.
    public static func scores(from response: SystemOneResponse, facts: [Fact]) -> [FactScore] {
        facts.enumerated().map { index, fact in
            guard case let .score(answer)? = response.answers[questionID(index)] else { return FactScore(fact: fact, score: 0) }
            return FactScore(fact: fact, score: max(0, min(1, 1 - answer.probability(ofLevel: 0))))
        }
    }

    /// The facts that go: those at or above `threshold`, the highest
    /// `limit` of them, plus every fact noted within `alwaysWithin` of
    /// `now`; returned in the order the scores came (the store's order,
    /// oldest first), so the prompt's block reads as it always did.
    public static func select(_ scores: [FactScore], threshold: Double = threshold, limit: Int = maxSent, now: Date? = nil, alwaysWithin: TimeInterval = alwaysWithin) -> [Fact] {
        let ranked = scores.enumerated()
            .filter { $0.element.score >= threshold }
            .sorted { lhs, rhs in
                lhs.element.score != rhs.element.score ? lhs.element.score > rhs.element.score : lhs.offset < rhs.offset
            }
            .prefix(max(limit, 0))
        var chosen = Set(ranked.map(\.offset))
        if let now {
            for (index, scored) in scores.enumerated() where now.timeIntervalSince(scored.fact.date) < alwaysWithin {
                chosen.insert(index)
            }
        }
        return scores.enumerated().filter { chosen.contains($0.offset) }.map(\.element.fact)
    }
}

public struct FactScore: Equatable, Sendable {
    public var fact: Fact
    public var score: Double

    public init(fact: Fact, score: Double) {
        self.fact = fact
        self.score = score
    }
}

public enum FactPickVerdict: Equatable, Sendable {
    /// Jev scored every fact, in the order given; `requests` were sent at
    /// once and `latencyMs` is the wall time of the slowest.
    case scored([FactScore], latencyMs: Int, requests: Int)
    /// A request failed or timed out; nothing is kept of the others, since
    /// a partial list would drop facts in silence. Every fact goes instead.
    case failed(String)
}

/// Sends the facts to Jev in requests of `chunk`, all at once, and reads
/// the scores back. Never throws.
public struct FactPicker: Sendable {
    public var client: JevClient
    public var locale: Locale
    public var chunk: Int

    public init(client: JevClient, locale: Locale = .current, chunk: Int = FactPicking.chunk) {
        self.client = client
        self.locale = locale
        self.chunk = chunk
    }

    /// A client for the pick: its own model and a short timeout.
    public static func client(apiKey: String) -> JevClient {
        JevClient(apiKey: apiKey, model: FactPicking.model, timeout: FactPicking.timeout)
    }

    public func pick(_ query: String, facts: [Fact], exchanges: [Exchange] = []) async -> FactPickVerdict {
        guard !facts.isEmpty else { return .scored([], latencyMs: 0, requests: 0) }
        let parts = FactPicking.chunks(facts, size: chunk)
        let clock = ContinuousClock()
        let start = clock.now
        let client = client
        let locale = locale
        let answers: [Int: Result<SystemOneResponse, JevError>] = await withTaskGroup(of: (Int, Result<SystemOneResponse, JevError>).self) { group in
            for (index, part) in parts.enumerated() {
                group.addTask {
                    let request = FactPicking.request(for: query, facts: part, exchanges: exchanges, locale: locale, model: client.model)
                    do throws(JevError) {
                        return (index, .success(try await client.systemOne(request)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [Int: Result<SystemOneResponse, JevError>] = [:]
            for await (index, result) in group { collected[index] = result }
            return collected
        }
        let latency = Int((clock.now - start) / .milliseconds(1))
        var scores: [FactScore] = []
        for (index, part) in parts.enumerated() {
            switch answers[index] {
            case let .success(response)?:
                scores += FactPicking.scores(from: response, facts: part)
            case let .failure(error)?:
                return .failed(error.summary)
            case nil:
                return .failed("no answer")
            }
        }
        return .scored(scores, latencyMs: latency, requests: parts.count)
    }
}

/// How a query's facts were chosen, on the decision's line: how many were
/// held, how many went, how long Jev took, and whether every fact went
/// instead and why.
public struct FactPickSummary: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable {
        /// Jev scored them and the selection went.
        case picked
        /// Every fact went: Jev failed, was too slow, or there was no key.
        case all
    }

    public var model: String
    public var held: Int
    public var sent: Int
    public var outcome: Outcome
    /// Why every fact went, when it did.
    public var reason: String?
    public var latencyMs: Int?
    public var requests: Int?
    /// The words scored: the read words after a rewrite.
    public var query: String?
    /// How many times a plan called `facts` to look further.
    public var lookups: Int?

    public init(model: String = FactPicking.model, held: Int, sent: Int, outcome: Outcome, reason: String? = nil, latencyMs: Int? = nil, requests: Int? = nil, query: String? = nil, lookups: Int? = nil) {
        self.model = model
        self.held = held
        self.sent = sent
        self.outcome = outcome
        self.reason = reason
        self.latencyMs = latencyMs
        self.requests = requests
        self.query = query
        self.lookups = lookups
    }

    /// Every fact went because of `reason`.
    public static func all(held: Int, reason: String, latencyMs: Int? = nil, query: String? = nil) -> FactPickSummary {
        FactPickSummary(held: held, sent: held, outcome: .all, reason: reason, latencyMs: latencyMs, query: query)
    }
}

/// The facts a query's answer and plan get, with the line for the log; nil
/// summary when there were no facts to choose among.
public struct FactSelection: Sendable, Equatable {
    public var facts: [Fact]
    public var summary: FactPickSummary?

    public init(facts: [Fact], summary: FactPickSummary?) {
        self.facts = facts
        self.summary = summary
    }

    /// From a verdict over `held`: the selection, or every fact on a failure.
    public static func from(_ verdict: FactPickVerdict, held: [Fact], query: String, now: Date = .now) -> FactSelection {
        guard !held.isEmpty else { return FactSelection(facts: [], summary: nil) }
        switch verdict {
        case let .scored(scores, latencyMs, requests):
            let picked = FactPicking.select(scores, now: now)
            return FactSelection(facts: picked, summary: FactPickSummary(held: held.count, sent: picked.count, outcome: .picked, latencyMs: latencyMs, requests: requests, query: query))
        case let .failed(reason):
            return FactSelection(facts: held, summary: .all(held: held.count, reason: reason, query: query))
        }
    }

    /// Every fact, for when there is no picker or the wait ran out.
    public static func all(_ held: [Fact], reason: String, query: String) -> FactSelection {
        FactSelection(facts: held, summary: held.isEmpty ? nil : .all(held: held.count, reason: reason, query: query))
    }
}
