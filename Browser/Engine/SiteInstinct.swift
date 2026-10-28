import Foundation
import Routing
import Sites

/// A website by name: the reading's subject, or the words as typed. An
/// address loads as is; a name the book knows opens at once; an unknown
/// name is searched and the choices shown, or the results page stands in
/// when nothing can be searched. Over a site this app opened by name, Jev's
/// `rejects` answer is this instinct's to act on: the name is forgotten and
/// the choices come back.
struct SiteInstinct: InstinctRunner {
    let spec = InstinctSpec.spec(for: .site)

    func run(_ context: InstinctContext, in session: BrowserSession, token: UUID) async -> InstinctOutcome {
        let name = context.arguments["name"]?.stringValue ?? context.query
        if let url = QueryParser.directURL(from: name) {
            session.openPage(url, context: context)
            return .nothing
        }
        // A rejection forgets what the name meant, then asks again.
        if context.decision.rejectsSite { await session.sites.forget(name) }
        if let entry = await session.sites.lookup(name) {
            guard session.isCurrent(token) else { return .nothing }
            await session.sites.touch(name)
            session.openSite(name, url: entry.url, context: context)
            session.record(context, site: SiteSummary(name: name, outcome: "opened", host: entry.host))
            return .nothing
        }
        guard session.isCurrent(token) else { return .nothing }
        await findSites(for: name, context: context, in: session, token: token)
        return .nothing
    }

    /// The sites `name` might mean, from the search: the choices card.
    /// Without a client, with nothing found, or on any failure the Google
    /// results page for the name stands in, and the first site tapped off
    /// it is learned instead.
    private func findSites(for name: String, context: InstinctContext, in session: BrowserSession, token: UUID) async {
        let outcome = context.decision.rejectsSite ? "rejected" : "choices"
        guard let siteSearch = session.siteSearch else {
            fellBackToResults(for: name, context: context, in: session, outcome: outcome, reason: "no key")
            return
        }
        session.stage = .loading
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let found = try await siteSearch.find(name)
            let latency = Int((clock.now - start) / .milliseconds(1))
            guard session.isCurrent(token) else { return }
            session.showCard(.siteChoices(name: name, found), context: context, recording: false)
            session.record(context, site: SiteSummary(name: name, outcome: outcome, candidates: found.count, latencyMs: latency))
        } catch {
            let latency = Int((clock.now - start) / .milliseconds(1))
            guard session.isCurrent(token) else { return }
            fellBackToResults(for: name, context: context, in: session, outcome: outcome, reason: Self.describe(error), latencyMs: latency)
        }
    }

    private func fellBackToResults(for name: String, context: InstinctContext, in session: BrowserSession, outcome: String, reason: String, latencyMs: Int? = nil) {
        #if DEBUG
        print("sites \"\(name)\": results page, \(reason)")
        #endif
        session.openResultsForSite(name, context: context)
        session.record(context, site: SiteSummary(name: name, outcome: outcome == "rejected" ? outcome : "results", reason: reason, latencyMs: latencyMs))
    }

    private static func describe(_ error: SiteError) -> String {
        switch error {
        case .timeout: "timeout"
        case .noResults: "no results"
        case let .transport(message): "transport: \(message)"
        case let .http(status, body): "http \(status): \(body)"
        case let .decoding(message): "decoding: \(message)"
        }
    }
}
