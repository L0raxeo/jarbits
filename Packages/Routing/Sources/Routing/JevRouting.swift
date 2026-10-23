import Foundation

/// The pure parts of routing: building the one Choice question and turning
/// Jev's answer into a decision. No I/O here, so every branch is testable.
public enum JevRouting {
    public static let questionID = "format"
    public static let recencyQuestionID = "recent"

    /// At or above this, a `narrative` or `one_line` pick is shown as web
    /// results: the model's knowledge is months old, and a confident wrong
    /// answer costs more than one extra tap. Revisit from the decision log.
    public static let recencyThreshold = 0.5

    /// Below this the answer is treated as "unsure" and the app shows web
    /// results. 0.5 is the floor TypeSafe's docs give for a genuinely unsure
    /// Choice; a wrong format here costs the user one extra tap, so it starts
    /// permissive. Revisit once the decision log has a few hundred rows.
    public static let confidenceFloor = 0.5

    public static let continuesQuestionID = "continues"

    /// At or above this, a `narrative` pick for a follow-up carries on the
    /// narrative on screen instead of starting a fresh one.
    public static let continuationThreshold = 0.5

    /// The previous answer is cut to this many characters before it goes to
    /// Jev: enough to judge a follow-up against, about 350 input tokens.
    public static let maxPreviousAnswerCharacters = 1500

    public static let instructions = """
        Which response format best answers this web search query? Judge the \
        query as typed. If several formats could work, prefer web_results.
        """

    /// The format question over a narrative on screen: the query is read as
    /// the conversation makes it. Built from the format list, so a card
    /// format added later is named here without another edit.
    public static var followUpInstructions: String {
        let cards = ResponseFormat.allCases.filter(\.outranksConversation).map(\.rawValue).joined(separator: ", ")
        return "Which response format best answers this web search query? The state carries the conversation so far: "
            + "the earlier queries and the answer on screen. Judge the query as that conversation makes it, not as typed on its own. "
            + "A reply, a reaction or a question that leans on the answer, however short, wants narrative, the format of the answer it replies to. "
            + "Pick another format only when the query asks for the kind of thing that format shows: \(cards), each described below; "
            + "or web_results for a page to browse."
    }

    public static let continuesInstructions = """
        The state carries the previous query and the answer the user is looking \
        at. Is this query a continuation of that exchange: a reply, a reaction, \
        a request to go on or to clarify, or a question that only makes sense \
        given that answer?
        """

    public static let continuesCriteria = (
        yes: "The query answers, reacts to, questions or builds on the previous answer, or would be incomplete without it, however short: \"why?\", \"can I use water\", \"and with oat milk\", \"tell me more\", \"is that true for cats too\".",
        no: "A new question that stands on its own, even about a nearby topic: it would mean the same thing with no previous answer."
    )

    public static let recencyInstructions = """
        Would the correct answer to this query depend on something that may have \
        changed in the last two years? For example whether a person is alive, who \
        currently holds an office, title or job, a record, a price, a recent event \
        or its aftermath, or a phrase, slogan or meme that became known recently.
        """

    public static let recencyCriteria = (
        yes: "The right answer could have changed since early 2025: it depends on someone's current status, the current holder of a position, a recent or ongoing event, or a new phrase.",
        no: "A settled fact, history, how something works, a definition, a conversion, a place, a date or time, or anything else that does not go stale."
    )

    /// `thread` is the narrative conversation on screen, oldest first, when
    /// the query was typed over one: its queries and last answer go into the
    /// state, the format question reads the query in that light, and the
    /// `continues` question is added.
    public static func request(for query: String, locale: Locale = .current, model: String = JevClient.defaultModel, thread: [AnswerTurn] = []) -> SystemOneRequest {
        var state = RouteState(query: query, locale: locale.identifier)
        var questions: [(id: String, question: Question)] = [
            (questionID, .choice(
                instructions: thread.isEmpty ? instructions : followUpInstructions,
                options: ResponseFormat.allCases.map { ($0.rawValue, $0.criterion) }
            )),
            (recencyQuestionID, .noul(instructions: recencyInstructions, criteria: recencyCriteria)),
        ]
        if let last = thread.last {
            state.previousQueries = thread.map(\.query)
            state.previousAnswer = String(last.answer.prefix(maxPreviousAnswerCharacters))
            questions.append((continuesQuestionID, .noul(instructions: continuesInstructions, criteria: continuesCriteria)))
        }
        return SystemOneRequest(model: model, state: state, questions: questions)
    }

    public static func decision(
        from response: SystemOneResponse,
        latencyMs: Int,
        floor: Double = confidenceFloor,
        recencyThreshold: Double = recencyThreshold
    ) -> RouteDecision {
        var recency: Double?
        if case let .noul(value)? = response.answers[recencyQuestionID] { recency = value }
        var continuation: Double?
        if case let .noul(value)? = response.answers[continuesQuestionID] { continuation = value }
        guard case let .choice(answer)? = response.answers[questionID] else {
            return RouteDecision(
                format: .fallback,
                model: response.model,
                latencyMs: latencyMs,
                inputTokens: response.usage.inputTokens,
                source: .error("no '\(questionID)' choice answer in response")
            )
        }
        guard let suggested = ResponseFormat(rawValue: answer.choice) else {
            return RouteDecision(
                format: .fallback,
                confidence: answer.confidence,
                probabilities: answer.probabilities,
                model: response.model,
                latencyMs: latencyMs,
                inputTokens: response.usage.inputTokens,
                source: .error("unknown format '\(answer.choice)'")
            )
        }
        let passes = answer.confidence >= floor
        let stale = (recency ?? 0) >= recencyThreshold
        let continues = (continuation ?? 0) >= continuationThreshold
        let (format, source): (ResponseFormat, RouteDecision.Source) = {
            if continues {
                // Over a narrative, the continuation decides the frame and the
                // pick decides the card: a confident ask for another kind of
                // card gets it; anything else, however a terse reply looked
                // on its own, carries the conversation on.
                if passes, suggested.outranksConversation { return (suggested, .jev) }
                if stale { return (.fallback, .recencyFallback) }
                return (.narrative, .continuation)
            }
            if !passes { return (.fallback, .confidenceFallback) }
            // Only formats a model answers are gated; web, map and stock show a page anyway.
            if suggested.isAnswered, stale { return (.fallback, .recencyFallback) }
            return (suggested, .jev)
        }()
        return RouteDecision(
            format: format,
            suggested: suggested,
            confidence: answer.confidence,
            probabilities: answer.probabilities,
            model: response.model,
            latencyMs: latencyMs,
            inputTokens: response.usage.inputTokens,
            recency: recency,
            continuation: continuation,
            source: source
        )
    }
}

/// Decides a format for a query: addresses bypass Jev, everything else is
/// asked, and any failure becomes the fallback format. Never throws.
public struct FormatRouter: Sendable {
    public var client: JevClient
    public var locale: Locale
    public var floor: Double

    public init(client: JevClient, locale: Locale = .current, floor: Double = JevRouting.confidenceFloor) {
        self.client = client
        self.locale = locale
        self.floor = floor
    }

    /// `thread` is the narrative conversation on screen, if any; with it Jev
    /// reads the query in that light and is asked whether it continues it.
    public func decide(_ query: String, thread: [AnswerTurn] = []) async -> RouteDecision {
        if QueryParser.directURL(from: query) != nil {
            return .directURL()
        }
        let request = JevRouting.request(for: query, locale: locale, model: client.model, thread: thread)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let response = try await client.systemOne(request)
            let latency = Int((clock.now - start) / .milliseconds(1))
            return JevRouting.decision(from: response, latencyMs: latency, floor: floor)
        } catch {
            let latency = Int((clock.now - start) / .milliseconds(1))
            return RouteDecision(format: .fallback, latencyMs: latency, source: .error(describe(error)))
        }
    }

    private func describe(_ error: JevError) -> String {
        switch error {
        case .timeout: "timeout"
        case let .transport(message): "transport: \(message)"
        case let .http(status, body): "http \(status): \(body)"
        case let .decoding(message): "decoding: \(message)"
        }
    }
}
