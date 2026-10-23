import Foundation
import Routing

/// Every query becomes a web card: URL-looking input loads directly,
/// anything else becomes a Google search. No model is consulted.
struct LocalRouter: Router {
    func route(_ query: String, thread: [AnswerTurn], opened: OpenedSite?) async -> RouteResult {
        if let url = QueryParser.directURL(from: query) {
            return RouteResult(plan: .web(url), decision: .directURL())
        }
        return RouteResult(plan: .web(QueryParser.searchURL(for: query)), decision: .noKey())
    }
}
