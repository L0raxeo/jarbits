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
    /// Reads a pick's free-form values out of the words; nil without a
    /// Gemini key, in which case an instinct that needs one is web results.
    let extractor: ValueExtractor?
    /// Plans a query that needs several steps; nil without a Gemini key, in
    /// which case such a query runs its pick like any other.
    let planner: Planner?
    let sites: SiteStore
    /// A Gemini key is configured, so an answer can be planned.
    let canAnswer: Bool
    let instincts: [any Instinct]

    init(router: EngineRouter?, extractor: ValueExtractor? = nil, planner: Planner? = nil, sites: SiteStore, canAnswer: Bool, instincts: [any Instinct] = InstinctRegistry.all()) {
        self.router = router
        self.extractor = extractor
        self.planner = planner
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
        // Several steps, a condition, or an unsure pick that leaned that
        // way: the session plans it instead of running the pick.
        if planner != nil, ReasoningPolicy.entersReasoning(decision) {
            return RouteResult(plan: nil, decision: decision, reasoning: true, chained: chained.map(\.exchange))
        }
        // The values the pick takes: what its grammars read (the device
        // rule's, then the pick's own), what Jev read for its closed-set
        // fields, and what a model reads out of the words for the free-form
        // ones still missing, when the field is required, the query is chained, or the reasoning
        // score says a value is in the words.
        let spec = InstinctSpec.spec(for: decision.format)
        var arguments = outcome.arguments.mapValues(JSONValue.string)
        for (name, value) in spec.read?(query) ?? [:] where arguments[name] == nil {
            arguments[name] = .string(value)
        }
        for (name, value) in decision.arguments ?? [:] where arguments[name] == nil {
            arguments[name] = .string(value)
        }
        var extraction: ExtractionSummary?
        let missing = spec.arguments.freeForm.filter { arguments[$0.name] == nil }
        // A chained query depends on the exchanges, so its words alone do
        // not name the value ("pictures of it", "wait no I meant brazil").
        if !missing.isEmpty, missing.contains(where: \.required) || (decision.reasoning ?? 0) >= EngineRouting.extractionThreshold || decision.chainedCount > 0 {
            if let extractor {
                let schema = spec.arguments.jsonSchema(only: missing)
                switch await extractor.extract(query: query, exchanges: chained.map(\.exchange), schema: schema) {
                case let .values(values, summary):
                    arguments.merge(spec.arguments.validate(values)) { _, read in read }
                    extraction = summary
                case let .failed(summary):
                    extraction = summary
                }
            } else {
                extraction = ExtractionSummary(model: "", latencyMs: 0, outcome: .failed("no key"))
            }
        }
        // A lasting fact the words state on the way to something else
        // ("I'm allergic to peanuts, what can I snack on"): Jev's remember
        // question says so, a model distils it, the session keeps it beside
        // the pick. The remember and forget instincts handle their own.
        var inferred: Fact?
        if decision.statesFact, decision.format != .remember, decision.format != .forget, let extractor {
            let (text, summary) = await extractor.distill(query: query, exchanges: chained.map(\.exchange))
            if let text { inferred = Fact(text: text, source: .inferred, madeBy: query) }
            if extraction == nil { extraction = summary }
        }
        if !spec.arguments.missingRequired(in: arguments).isEmpty {
            // A value the instinct cannot run without never came: the words go to the web.
            return RouteResult(plan: .web(QueryParser.searchURL(for: query)), decision: decision, extraction: extraction, inferred: inferred)
        }
        // A continuation grows the current answer: its own turns go as the
        // thread, so only exchanges from other layers are context there.
        let earlier = chained.filter { !(decision.continuesThread && $0.layerID == current?.id) }.map(\.exchange)
        let context = InstinctContext(
            query: query,
            outcome: outcome,
            opened: opened,
            canAnswer: canAnswer,
            thread: decision.continuesThread ? (current?.thread ?? []) : [],
            earlier: earlier,
            arguments: arguments
        )
        let instinct = instinct(for: decision.format)
        if !spec.showsLayer {
            return RouteResult(plan: nil, decision: decision, extraction: extraction, action: instinct, context: context, inferred: inferred)
        }
        return RouteResult(plan: instinct.plan(context), decision: decision, extraction: extraction, inferred: inferred)
    }

    private func instinct(for format: ResponseFormat) -> any Instinct {
        // The registry covers every format; `InstinctRegistry.all()` asserts it.
        instincts.first { $0.spec.format == format }!
    }
}

/// What to render, or the instinct to run when it shows nothing; the
/// decision behind it for the log; how reading the pick's values went
/// when a model was asked; and a fact the words stated on the way, for
/// the session to keep.
struct RouteResult {
    /// What to show; nil for an instinct that acts instead, or a query to plan.
    var plan: CardPlan?
    var decision: RouteDecision
    var extraction: ExtractionSummary? = nil
    /// The instinct to run when there is no plan, with what it needs.
    var action: (any Instinct)? = nil
    var context: InstinctContext? = nil
    var inferred: Fact? = nil
    /// The query goes to advanced reasoning, with these exchanges as what it depends on.
    var reasoning = false
    var chained: [Exchange] = []
}

extension BrowserSession {
    /// Jev behind the device's rules when a key is configured; without one
    /// the rules alone, and web results for the rest. Gemini reads a
    /// pick's free-form values when its key is configured.
    static func makeEngine(sites: SiteStore = .shared) -> Engine {
        let router = Secrets.typeSafeAPIKey.map { EngineRouter(client: JevClient(apiKey: $0)) }
        let extractor = Secrets.geminiAPIKey.map { ValueExtractor(client: GeminiClient(apiKey: $0)) }
        let planner = Secrets.geminiAPIKey.map { Planner(client: GeminiClient(apiKey: $0, model: Planner.model, totalTimeout: ReasoningPolicy.roundTimeout)) }
        return Engine(router: router, extractor: extractor, planner: planner, sites: sites, canAnswer: Secrets.geminiAPIKey != nil)
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

    /// Jev judging which fact a forget means, when a key is configured;
    /// nil offers the shortlist in word order.
    static func makeFactResolver() -> FactResolver? {
        Secrets.typeSafeAPIKey.map { FactResolver(client: JevClient(apiKey: $0)) }
    }

    /// Gemini when a key is configured; nil leaves the answer formats on web results.
    static func makeAnswerClient() -> GeminiClient? {
        Secrets.geminiAPIKey.map { GeminiClient(apiKey: $0) }
    }
}
