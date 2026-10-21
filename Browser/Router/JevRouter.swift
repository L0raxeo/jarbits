import Foundation
import Routing

/// Asks Jev which format answers the query, maps the format to a plan, and
/// records the decision. Only the web card exists today, so every format
/// still renders Google results; `plan(for:query:)` is where format two plugs in.
struct JevRouter: Router {
    var formatRouter: FormatRouter
    var log: DecisionLog

    func route(_ query: String) async -> RouteResult {
        let decision = await formatRouter.decide(query)
        let plan = plan(for: decision, query: query)
        let record = DecisionRecord(query: query, decision: decision)
        Task { await log.append(record) }
        return RouteResult(plan: plan, decision: decision)
    }

    private func plan(for decision: RouteDecision, query: String) -> CardPlan {
        if case .directURL = decision.source, let url = QueryParser.directURL(from: query) {
            return .web(url)
        }
        switch decision.format {
        case .webResults:
            return .web(QueryParser.searchURL(for: query))
        case .summary, .images, .map, .flights, .stock, .oneWord, .presentation, .videos, .links:
            // Not built yet: web results stand in. Moving a format out of this
            // branch and flipping its `stage` happen in the same change.
            assert(decision.format.stage == .routed, "\(decision.format) is marked \(decision.format.stage) but has no card")
            return .web(QueryParser.searchURL(for: query))
        }
    }
}

extension BrowserSession {
    /// Jev when a key is configured, the local fallback otherwise.
    static func makeRouter() -> any Router {
        guard let key = Secrets.typeSafeAPIKey else { return LocalRouter() }
        return JevRouter(formatRouter: FormatRouter(client: JevClient(apiKey: key)), log: .shared)
    }
}
