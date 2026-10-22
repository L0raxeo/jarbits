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

    public static let instructions = """
        Which response format best answers this web search query? Judge the \
        query as typed. If several formats could work, prefer web_results.
        """

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

    public static func request(for query: String, locale: Locale = .current, model: String = JevClient.defaultModel) -> SystemOneRequest {
        SystemOneRequest(
            model: model,
            state: RouteState(query: query, locale: locale.identifier),
            questions: [
                (questionID, .choice(
                    instructions: instructions,
                    options: ResponseFormat.allCases.map { ($0.rawValue, $0.criterion) }
                )),
                (recencyQuestionID, .noul(instructions: recencyInstructions, criteria: recencyCriteria)),
            ]
        )
    }

    public static func decision(
        from response: SystemOneResponse,
        latencyMs: Int,
        floor: Double = confidenceFloor,
        recencyThreshold: Double = recencyThreshold
    ) -> RouteDecision {
        var recency: Double?
        if case let .noul(value)? = response.answers[recencyQuestionID] { recency = value }
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
        // Only formats a model answers are gated; web, map and stock show a page anyway.
        let stale = passes && suggested.isAnswered && (recency ?? 0) >= recencyThreshold
        let source: RouteDecision.Source = !passes ? .confidenceFallback : stale ? .recencyFallback : .jev
        return RouteDecision(
            format: source == .jev ? suggested : .fallback,
            suggested: suggested,
            confidence: answer.confidence,
            probabilities: answer.probabilities,
            model: response.model,
            latencyMs: latencyMs,
            inputTokens: response.usage.inputTokens,
            recency: recency,
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

    public func decide(_ query: String) async -> RouteDecision {
        if QueryParser.directURL(from: query) != nil {
            return .directURL()
        }
        let request = JevRouting.request(for: query, locale: locale, model: client.model)
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
