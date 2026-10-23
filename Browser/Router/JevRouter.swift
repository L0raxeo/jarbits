import Answers
import Foundation
import Routing

/// Asks Jev which format answers the query and maps the format to a plan.
/// `narrative` and `one_line` become answer cards when a Gemini key is
/// configured, `image` a Wikipedia picture; `map` and `stock` still render
/// web results.
struct JevRouter: Router {
    var formatRouter: FormatRouter
    /// Without a Gemini key the answer formats fall back to web results and
    /// the Debug ribbon says so.
    var canAnswer: Bool

    func route(_ query: String) async -> RouteResult {
        let decision = await formatRouter.decide(query)
        return RouteResult(plan: plan(for: decision, query: query), decision: decision)
    }

    private func plan(for decision: RouteDecision, query: String) -> CardPlan {
        if case .directURL = decision.source, let url = QueryParser.directURL(from: query) {
            return .web(url)
        }
        switch decision.format {
        case .webResults:
            return .web(QueryParser.searchURL(for: query))
        case .narrative, .oneLine:
            assert(decision.format.stage >= .built, "\(decision.format) has a card but is marked \(decision.format.stage)")
            return canAnswer ? .answer(format: decision.format, query: query) : .web(QueryParser.searchURL(for: query))
        case .image:
            assert(decision.format.stage == .built, "image is marked \(decision.format.stage)")
            return .image(query: query)
        case .map, .stock:
            // Not built yet: web results stand in. Moving a format out of this
            // branch and flipping its `stage` happen in the same change.
            assert(decision.format.stage == .routed, "\(decision.format) is marked \(decision.format.stage) but has no card")
            return .web(QueryParser.searchURL(for: query))
        }
    }
}

extension BrowserSession {
    /// The device's own rules first; behind them Jev when a key is configured, the local fallback otherwise.
    static func makeRouter() -> any Router {
        guard let key = Secrets.typeSafeAPIKey else { return LocalFirstRouter(inner: LocalRouter()) }
        return LocalFirstRouter(inner: JevRouter(formatRouter: FormatRouter(client: JevClient(apiKey: key)), canAnswer: Secrets.geminiAPIKey != nil))
    }

    /// Gemini when a key is configured; nil leaves the answer formats on web results.
    static func makeAnswerClient() -> GeminiClient? {
        Secrets.geminiAPIKey.map { GeminiClient(apiKey: $0) }
    }
}
