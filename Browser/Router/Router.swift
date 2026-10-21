import Foundation
import Routing

/// The seam between a query and what the app shows for it.
///
/// `JevRouter` asks the System One model which format fits; `LocalRouter` is
/// the no-network fallback used when no API key is configured.
protocol Router: Sendable {
    func route(_ query: String) async -> RouteResult
}

/// What to render, and the decision behind it for the debug ribbon and the log.
struct RouteResult: Sendable {
    var plan: CardPlan
    var decision: RouteDecision
}
