import Foundation
import Engine

/// What an instinct runs on: the words that ran (the reading's, when it
/// rewrote them), Jev's pick, the site on screen,
/// whether an answer can be shown, the thread a continuation grows, the
/// exchanges from other layers the query depends on, the values the
/// instinct takes, and what rides on the log line beside the pick.
struct InstinctContext {
    let query: String
    let decision: Pick
    let opened: OpenedSite?
    let canAnswer: Bool
    /// The conversation on screen, oldest first, when the query continues
    /// it; empty otherwise.
    let thread: [AnswerTurn]
    /// The chained exchanges that are not the thread: a search made, a page
    /// read, a picture looked at; oldest first.
    let earlier: [Exchange]
    /// The values the instinct takes, by field name: what Jev read for a
    /// closed-set field, what the extractor read for a free-form one, or
    /// what a plan passed.
    let arguments: [String: JSONValue]
    /// How the extractor fared, when it was asked; for the log.
    var extraction: ExtractionSummary? = nil
    /// How the reading beside Jev fared, when it ran; for the log.
    var reading: ReadingSummary? = nil
    /// A lasting fact the words stated on the way, kept beside the pick; for the log.
    var fact: FactSummary? = nil
}

/// What an instinct that shows nothing came to: how it touched the facts,
/// and a line for the console. A showing instinct returns `.nothing`.
struct InstinctOutcome {
    var fact: FactSummary?
    var text: String

    static let nothing = InstinctOutcome(fact: nil, text: "")
}

/// One instinct as the app runs it: its spec from the registry, and what it
/// does for a query Jev picked it for, through the session: a showing
/// instinct opens its layer and records its line; an acting one works the
/// session's stores and sheet and hands back what to log. Nothing else
/// dispatches on the pick.
protocol InstinctRunner {
    var spec: InstinctSpec { get }
    /// Runs under the request's token: a wait that outlives the query lands nowhere.
    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome
}

enum InstinctRegistry {
    /// One conformer per spec, in registry order.
    static func all() -> [any InstinctRunner] {
        let instincts: [any InstinctRunner] = [
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
            TimeInstinct(),
        ]
        assert(instincts.map(\.spec.id) == InstinctSpec.all.map(\.id), "every spec in the registry has its conformer, in order")
        return instincts
    }
}
