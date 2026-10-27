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
    /// The values the instinct takes, by field name: what its grammar read,
    /// what Jev read for a closed-set field, what a model read out of the
    /// words for a free-form one. Empty for an instinct that takes none.
    let arguments: [String: JSONValue]

    var decision: RouteDecision { outcome.decision }
}

/// What an instinct that shows nothing came to: how it touched the facts,
/// and a line for the console.
struct ActOutcome {
    var fact: FactSummary?
    var text: String

    static let nothing = ActOutcome(fact: nil, text: "")
}

/// One instinct as the app runs it: its spec from the registry, and either
/// the plan it makes for a query the engine decided for it (the session
/// turns the plan into a layer) or, for one that shows nothing, what it
/// does with the session's stores and sheet.
protocol Instinct {
    var spec: InstinctSpec { get }
    /// The plan of a showing instinct; an acting one is never asked for it.
    func plan(_ context: InstinctContext) -> CardPlan
    /// What an acting instinct (`spec.showsLayer == false`) does, under the
    /// request's token: a wait that outlives the query is answered nothing.
    func act(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> ActOutcome
}

extension Instinct {
    func act(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> ActOutcome {
        .nothing
    }
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
            RememberInstinct(),
            ForgetInstinct(),
        ]
        assert(instincts.map(\.spec.id) == InstinctSpec.all.map(\.id), "every spec in the registry has its conformer, in order")
        return instincts
    }
}
