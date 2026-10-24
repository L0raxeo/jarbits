import Answers
import Foundation
import Images
import Routing
import Sites

/// Asks Jev which format answers the query and maps the format to a plan.
/// `narrative` and `one_line` become answer cards when a Gemini key is
/// configured, `image` a Wikipedia picture (Brave's behind it), `video`
/// Google's video results for the term, `recall` a look through the
/// memories, `site` a look in the site book; `map` and `stock` still render
/// web results.
struct JevRouter: Router {
    var formatRouter: FormatRouter
    /// Without a Gemini key the answer formats fall back to web results and
    /// the Debug ribbon says so.
    var canAnswer: Bool

    /// Jev reads the query in the light of `thread`; a decision that
    /// continues the thread carries the whole thread into the answer plan.
    /// Over `opened`, a decision that rejects it is a site plan for the same
    /// name again.
    func route(_ query: String, thread: [AnswerTurn], opened: OpenedSite?) async -> RouteResult {
        let decision = await formatRouter.decide(query, thread: thread, opened: opened)
        return RouteResult(plan: plan(for: decision, query: query, thread: thread, opened: opened), decision: decision)
    }

    private func plan(for decision: RouteDecision, query: String, thread: [AnswerTurn], opened: OpenedSite?) -> CardPlan {
        if case .directURL = decision.source, let url = QueryParser.directURL(from: query) {
            return .web(url)
        }
        switch decision.format {
        case .webResults:
            // The verb that asked for the search ("google steve jobs") stays out of the box.
            return .web(QueryParser.searchURL(for: SearchQuery.term(for: query)))
        case .narrative, .oneLine:
            assert(decision.format.stage >= .built, "\(decision.format) has a card but is marked \(decision.format.stage)")
            guard canAnswer else { return .web(QueryParser.searchURL(for: query)) }
            return .answer(format: decision.format, query: query, history: decision.continuesThread ? thread : [])
        case .image:
            assert(decision.format.stage == .built, "image is marked \(decision.format.stage)")
            return .image(query: query)
        case .video:
            // Google's video results for the term, with the asking gone.
            assert(decision.format.stage == .built, "video is marked \(decision.format.stage)")
            return .web(QueryParser.videoSearchURL(for: VideoQuery.term(for: query)))
        case .recall:
            assert(decision.format.stage == .built, "recall is marked \(decision.format.stage)")
            return .recall(query: query)
        case .site:
            assert(decision.format.stage == .built, "site is marked \(decision.format.stage)")
            if decision.rejectsSite, let opened { return .site(name: opened.name) }
            return .site(name: SiteQuery.parse(query)?.name ?? query)
        case .map, .stock:
            // Not built yet: web results stand in. Moving a format out of this
            // branch and flipping its `stage` happen in the same change.
            assert(decision.format.stage == .routed, "\(decision.format) is marked \(decision.format.stage) but has no card")
            return .web(QueryParser.searchURL(for: query))
        }
    }
}

extension BrowserSession {
    /// The device's own rules first; behind them Jev when a key is configured, the local fallback otherwise.
    static func makeRouter(sites: SiteStore = .shared) -> any Router {
        let canAnswer = Secrets.geminiAPIKey != nil
        guard let key = Secrets.typeSafeAPIKey else { return LocalFirstRouter(inner: LocalRouter(), sites: sites, canAnswer: canAnswer) }
        return LocalFirstRouter(inner: JevRouter(formatRouter: FormatRouter(client: JevClient(apiKey: key)), canAnswer: canAnswer), sites: sites, canAnswer: canAnswer)
    }

    /// Brave's web search for the sites an unknown name might mean, when a
    /// key is configured; nil shows the Google results page for the name.
    static func makeSiteSearch() -> SiteSearch? {
        Secrets.braveAPIKey.map { SiteSearch(apiKey: $0) }
    }

    /// Wikipedia first for a picture; Brave's image search behind it when a
    /// key is configured, else a Wikipedia miss goes to Google Images.
    static func makeImageLookup() -> ImageLookup {
        ImageLookup(wikipedia: ImageSearch(), brave: Secrets.braveAPIKey.map { BraveImageSearch(apiKey: $0) })
    }

    /// Jev judging a recall shortlist, when a key is configured; nil shows
    /// the shortlist in word order.
    static func makeRecallResolver() -> RecallResolver? {
        Secrets.typeSafeAPIKey.map { RecallResolver(client: JevClient(apiKey: $0)) }
    }

    /// Gemini when a key is configured; nil leaves the answer formats on web results.
    static func makeAnswerClient() -> GeminiClient? {
        Secrets.geminiAPIKey.map { GeminiClient(apiKey: $0) }
    }
}
