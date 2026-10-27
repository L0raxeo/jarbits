import Foundation
import Routing

/// What an instinct makes its plan from: the query, the engine's outcome
/// (the decision, and what the grammars read out of the words: the search
/// term, the picture's subject, the site's name, the device's own answer),
/// the site on screen, whether an answer can be planned, the thread a
/// continuation grows, and the exchanges from other layers the query
/// depends on.
struct InstinctContext {
    let query: String
    let outcome: RouteOutcome
    let opened: OpenedSite?
    let canAnswer: Bool
    /// The conversation on screen, oldest first, when the query continues
    /// it; empty otherwise.
    let thread: [AnswerTurn]
    /// The chained exchanges that are not the thread: a search made, a page
    /// read, a picture looked at; oldest first.
    let earlier: [Exchange]

    var decision: RouteDecision { outcome.decision }
}

/// One instinct as the app runs it: its spec from the registry, and the
/// plan it makes for a query the engine decided for it. The session turns
/// the plan into a layer.
protocol Instinct {
    var spec: InstinctSpec { get }
    func plan(_ context: InstinctContext) -> CardPlan
}

enum InstinctRegistry {
    /// One conformer per spec, in registry order.
    static func all() -> [any Instinct] {
        let instincts: [any Instinct] = [
            WebResultsInstinct(),
            AnswerInstinct(format: .narrative),
            MapInstinct(),
            StockInstinct(),
            AnswerInstinct(format: .oneLine),
            RecallInstinct(),
            ImageInstinct(),
            SiteInstinct(),
            VideoInstinct(),
        ]
        assert(instincts.map(\.spec.id) == InstinctSpec.all.map(\.id), "every spec in the registry has its conformer, in order")
        return instincts
    }
}
