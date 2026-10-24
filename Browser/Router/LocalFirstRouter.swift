import Foundation
import Routing

/// The device's own rules before any model: a query `LocalAnswers` can answer
/// (today, the time in a named place) becomes a one-line card at once, a
/// question handed to the model by name ("ask AI what GDP means") is a
/// narrative with no format question and no recency gate, a request to open
/// a site whose name the book knows ("go to youtube") opens it, and a query
/// led by a verb that only ever means "search" ("look up steve jobs") is
/// web results for the term, with no key and no network; everything else
/// goes to `inner`. Order against the address check inside `inner` does not
/// matter: an address has no spaces, and every local rule needs several
/// words. The same rules, in the same order, are `DeviceRouting` in the
/// package, which the report CLI and the eval run.
struct LocalFirstRouter: Router {
    static let askRule = DeviceRouting.askRule
    static let siteRule = DeviceRouting.siteRule
    static let searchRule = DeviceRouting.searchRule

    let inner: any Router
    let sites: SiteStore
    /// Without a Gemini key an explicit ask falls through to `inner`.
    var canAnswer: Bool

    func route(_ query: String, thread: [AnswerTurn], opened: OpenedSite?) async -> RouteResult {
        if let local = LocalAnswers.answer(query) {
            return RouteResult(
                plan: .localAnswer(format: local.format, query: query, text: local.text),
                decision: .local(local.rule, format: local.format)
            )
        }
        // "ask AI what are some alternatives to dyson": the user named the
        // model, so the question is its answer. The plan keeps the words as
        // typed (the session matches the answer to them); `AnswerSession`
        // sends the question alone.
        if canAnswer, AnswerQuery.parse(query) != nil {
            return RouteResult(plan: .answer(format: .narrative, query: query, history: []), decision: .local(Self.askRule, format: .narrative))
        }
        // An opener and a known name: the site, no model asked. A bare name
        // ("youtube") is left to Jev, which may read it as a search.
        if let site = SiteQuery.parse(query), site.hasOpener, await sites.lookup(site.name) != nil {
            return RouteResult(plan: .site(name: site.name), decision: .local(Self.siteRule, format: .site))
        }
        // "search for X", "look up X": web results for X. A bare "google X"
        // is not a command here ("google stock"); Jev decides, and the web
        // branch of its router drops the verb.
        if let search = SearchQuery.parse(query), search.isCommand {
            return RouteResult(plan: .web(QueryParser.searchURL(for: search.term)), decision: .local(Self.searchRule, format: .webResults))
        }
        return await inner.route(query, thread: thread, opened: opened)
    }
}
