import Foundation
import Engine

/// What an instinct runs on: the words that ran (the reading's, when it
/// rewrote them), Jev's pick, the site on screen,
/// whether an answer can be shown, the thread a continuation grows, the
/// exchanges from other layers the query depends on, the values the
/// instinct takes, and what rides on the log line beside the pick.
struct InstinctContext {
    let query: String
    /// Jev's pick, or the planner's step; an answer step about the
    /// conversation on screen sets `continues` on it.
    var decision: Pick
    let opened: OpenedSite?
    let canAnswer: Bool
    /// The conversation on screen, oldest first, when the query continues
    /// it; empty otherwise.
    var thread: [AnswerTurn]
    /// The chained exchanges that are not the thread: a search made, a page
    /// read, a picture looked at; oldest first.
    var earlier: [Exchange]
    /// The values the instinct takes, by field name: what Jev read for a
    /// closed-set field, what the extractor read for a free-form one, or
    /// what a plan passed.
    let arguments: [String: JSONValue]
    /// The things the instinct's thing fields name, resolved by the device:
    /// in a plan from the handle table, on the pick path from what the
    /// query leans on.
    var things: [String: Reference] = [:]
    /// Every thing a field named when it named several handles ("s5, s6");
    /// `things` holds the first.
    var manyThings: [String: [Reference]] = [:]
    /// Things the plan named in braces inside a text value ("- {s3}"), by
    /// handle, resolved by the device like any other handle.
    var namedThings: [String: Reference] = [:]
    /// A recall in a plan: return what was found, show nothing.
    var lookup = false
    /// How the extractor fared, when it was asked; for the log.
    var extraction: ExtractionSummary? = nil
    /// How the reading beside Jev fared, when it ran; for the log.
    var reading: ReadingSummary? = nil
    /// A lasting fact the words stated on the way, kept beside the pick; for the log.
    var fact: FactSummary? = nil
    /// What was on screen as the query began: an answer about it reads it.
    var screen: Screen? = nil
    /// The page this step opens goes to Jarbits's own screen, not the
    /// user's: the planner's choice, carried out by the session.
    var desk = false
    /// The user asked for a new webpage of a site already open: opened
    /// afresh instead of the open one coming forward.
    var fresh = false
}

/// What an instinct that shows nothing came to: how it touched the facts,
/// and a line for the console. A showing instinct returns `.nothing`.
struct InstinctOutcome {
    var fact: FactSummary?
    var text: String
    /// What a recall in a plan found, for the plan to point at by handle.
    var found: [Webpage] = []
    /// The instinct could not do the thing: why, in Jarbits's words. It
    /// showed nothing and recorded nothing; the session hands the query to
    /// the planner, and a plan step reads it as its result.
    var failed: String? = nil
    /// The user said no to the instinct's own question ("Delete my note
    /// X?" → Keep): the instinct showed what it showed, and the plan is
    /// over. The planner never gets a turn after a no, so it reports
    /// nothing about it; the device already showed the outcome.
    var declined = false

    static let nothing = InstinctOutcome(fact: nil, text: "")
    static func failed(_ reason: String) -> InstinctOutcome { InstinctOutcome(fact: nil, text: reason, failed: reason) }
    static func declined(_ text: String) -> InstinctOutcome { InstinctOutcome(fact: nil, text: text, declined: true) }
}

/// One instinct as the app runs it: its spec from the registry, and what it
/// does for a query Jev picked it for, through the session: a showing
/// instinct opens its layer and records its line; an acting one works the
/// session's stores and sheet and hands back what to log. Nothing else
/// dispatches on the pick.
protocol InstinctRunner {
    var spec: InstinctSpec { get }
    /// Runs under the request's token: a wait that outlives the query lands nowhere.
    func run(_ context: InstinctContext, in session: JarbitsSession, token: UUID) async -> InstinctOutcome
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
            NotebookInstinct(),
        ]
        assert(instincts.map(\.spec.id) == InstinctSpec.all.map(\.id), "every spec in the registry has its conformer, in order")
        return instincts
    }
}
