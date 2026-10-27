import Answers
import Foundation
import Images
import Routing
import Sites

/// The cognitive engine: a query in, a plan out. The device's own rules go
/// first and cost nothing (each instinct's grammar, in the order
/// `InstinctSpec.deviceRuleOrder` gives); then one Jev request over the
/// registry, carrying this session's earlier exchanges, when a key is
/// configured; then the chosen instinct makes its plan. The exchanges the
/// query depends on come back as the chain: the current answer's own turns
/// are the thread a continuation grows, anything else chained reaches the
/// instinct as context.
struct Engine {
    /// Jev; nil when no key is configured, in which case anything that is
    /// not an address or a device rule is web results.
    let router: EngineRouter?
    let sites: SiteStore
    /// A Gemini key is configured, so an answer can be planned.
    let canAnswer: Bool
    let instincts: [any Instinct]

    init(router: EngineRouter?, sites: SiteStore, canAnswer: Bool, instincts: [any Instinct] = InstinctRegistry.all()) {
        self.router = router
        self.sites = sites
        self.canAnswer = canAnswer
        self.instincts = instincts
    }

    /// `exchanges` is the session's history up to the layer on screen,
    /// oldest first; `current` that layer; `opened` a site this app opened
    /// by name and still shows.
    func route(_ query: String, exchanges: [SessionExchange], current: Layer?, opened: OpenedSite?) async -> RouteResult {
        let book = await sites.snapshot()
        let sent = Array(exchanges.suffix(EngineRouting.maxExchanges))
        let outcome: RouteOutcome
        if let device = DeviceRouting.decide(query, book: book, canAnswer: canAnswer) {
            outcome = device
        } else if let router {
            let decision = await router.decide(query, exchanges: sent.map(\.exchange), opened: opened)
            outcome = RouteOutcome(query: query, decision: decision, opened: opened)
        } else if QueryParser.directURL(from: query) != nil {
            outcome = RouteOutcome(query: query, decision: .directURL())
        } else {
            outcome = RouteOutcome(query: query, decision: .noKey())
        }
        let decision = outcome.decision
        let chained = Array(sent.suffix(decision.chainedCount))
        // A continuation grows the current answer: its own turns go as the
        // thread, so only exchanges from other layers are context there.
        let earlier = chained.filter { !(decision.continuesThread && $0.layerID == current?.id) }.map(\.exchange)
        let context = InstinctContext(
            query: query,
            outcome: outcome,
            opened: opened,
            canAnswer: canAnswer,
            thread: decision.continuesThread ? (current?.thread ?? []) : [],
            earlier: earlier
        )
        return RouteResult(plan: instinct(for: decision.format).plan(context), decision: decision)
    }

    private func instinct(for format: ResponseFormat) -> any Instinct {
        // The registry covers every format; `InstinctRegistry.all()` asserts it.
        instincts.first { $0.spec.format == format }!
    }
}

/// What to render, and the decision behind it for the log.
struct RouteResult: Sendable {
    var plan: CardPlan
    var decision: RouteDecision
}

extension BrowserSession {
    /// Jev behind the device's rules when a key is configured; without one
    /// the rules alone, and web results for the rest.
    static func makeEngine(sites: SiteStore = .shared) -> Engine {
        let router = Secrets.typeSafeAPIKey.map { EngineRouter(client: JevClient(apiKey: $0)) }
        return Engine(router: router, sites: sites, canAnswer: Secrets.geminiAPIKey != nil)
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
