import Foundation
import Routing

/// The seam between a query and what the app shows for it.
///
/// `JevRouter` asks the System One model which format fits; `LocalRouter` is
/// the no-network fallback used when no API key is configured.
protocol Router: Sendable {
    /// `thread` is the narrative conversation on screen, oldest first, when
    /// the query was typed over one; empty otherwise. A router that asks Jev
    /// lets it judge whether the query continues it. `opened` is a site
    /// this app opened by name and still shows; a router that asks Jev
    /// lets it judge whether the query rejects it.
    func route(_ query: String, thread: [AnswerTurn], opened: OpenedSite?) async -> RouteResult
}

/// What to render, and the decision behind it for the debug ribbon and the log.
struct RouteResult: Sendable {
    var plan: CardPlan
    var decision: RouteDecision
}
