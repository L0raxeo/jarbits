import Answers
import Foundation
import Engine
import Sites

/// The cognitive engine: a query in, the instinct to run out. An address
/// loads as typed, with nothing asked. Everything else goes to Jev in one
/// request over the registry, carrying this session's earlier exchanges,
/// with the reading beside it: one small Gemini call that returns the
/// request standing on its own. A reading that rewrote the words sends Jev
/// the read words again, and that pick wins. The extractor then reads every
/// free-form value the picked instinct declares out of the read words. A
/// query whose reasoning score says it needs several steps goes to the
/// executor instead. No word list decides anything here.
struct Engine {
    /// Jev; nil when no key is configured, in which case anything that is
    /// not an address is web results.
    let router: Picker?
    /// The reading beside Jev; nil without a Gemini key, in which case the
    /// typed words run as they are.
    let reader: QueryReader?
    /// Reads a pick's free-form values out of the words; nil without a
    /// Gemini key, in which case an instinct that needs one is web results.
    let extractor: ValueExtractor?
    /// Plans a query that needs several steps; nil without a Gemini key, in
    /// which case such a query runs its pick like any other.
    let planner: Planner?
    /// A Gemini key is configured, so an answer can be shown.
    let canAnswer: Bool
    let instincts: [any InstinctRunner]

    init(router: Picker?, reader: QueryReader? = nil, extractor: ValueExtractor? = nil, planner: Planner? = nil, canAnswer: Bool, instincts: [any InstinctRunner] = InstinctRegistry.all()) {
        self.router = router
        self.reader = reader
        self.extractor = extractor
        self.planner = planner
        self.canAnswer = canAnswer
        self.instincts = instincts
    }

    /// `exchanges` is the session's history up to the layer on screen,
    /// oldest first; `current` that layer; `opened` a site this app opened
    /// by name and still shows.
    func route(_ typed: String, exchanges: [SessionExchange], current: Layer?, opened: OpenedSite?, persona: Persona = Persona()) async -> EngineResult {
        let sent = Array(exchanges.suffix(EngineRequest.maxExchanges))
        var query = typed
        var reading: ReadingSummary?
        let decision: Pick
        if QueryParser.directURL(from: typed) != nil {
            decision = .directURL()
        } else if let router {
            // The reading runs beside the Jev request; a reading that only
            // touched case or punctuation never asks Jev twice.
            async let asked: ReadingSummary? = reader?.read(typed, exchanges: sent.map(\.exchange), persona: persona)
            let first = await router.decide(typed, exchanges: sent.map(\.exchange), opened: opened)
            reading = await asked
            if let read = reading?.query, reading?.changed == true {
                query = read
                decision = await router.decide(read, exchanges: sent.map(\.exchange), opened: opened)
            } else {
                decision = first
            }
        } else {
            decision = .noKey()
        }
        let chained = Array(sent.suffix(decision.chainedCount))
        // Several steps, a condition, or an unsure pick that leaned that
        // way: the session plans it instead of running the pick.
        if planner != nil, ReasoningPolicy.entersReasoning(decision) {
            return EngineResult(query: query, decision: decision, reading: reading, reasoning: true, chained: chained.map(\.exchange))
        }
        // The values the pick takes: what Jev read for its closed-set
        // fields, and what the extractor reads out of the words for every
        // free-form field the instinct declares.
        let spec = InstinctSpec.spec(for: decision.instinct)
        var arguments: [String: JSONValue] = [:]
        for (name, value) in decision.arguments ?? [:] {
            arguments[name] = .string(value)
        }
        var extraction: ExtractionSummary?
        // A remember pick's fact is read by the fact reader, the same call
        // that notes a fact stated on the way to another pick: it keeps the
        // whole sentence, naming whoever it is about.
        if decision.instinct == .remember, let extractor {
            let (text, summary) = await extractor.distill(query: query, exchanges: chained.map(\.exchange), persona: persona)
            if let text { arguments["fact"] = .string(text) }
            extraction = summary
        }
        let missing = spec.arguments.freeForm.filter { arguments[$0.name] == nil }
        if !missing.isEmpty {
            if let extractor {
                let schema = spec.arguments.jsonSchema(only: missing)
                switch await extractor.extract(query: query, exchanges: chained.map(\.exchange), schema: schema, instructions: ValueExtractor.system(persona), now: .now) {
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
        if decision.statesFact, decision.instinct != .remember, decision.instinct != .forget, let extractor {
            let (text, summary) = await extractor.distill(query: query, exchanges: chained.map(\.exchange), persona: persona)
            if let text { inferred = Fact(text: text, source: .inferred, madeBy: query) }
            if extraction == nil { extraction = summary }
        }
        // A continuation grows the current answer: its own turns go as the
        // thread, so only exchanges from other layers are context there.
        let earlier = chained.filter { !(decision.continuesThread && $0.layerID == current?.id) }.map(\.exchange)
        // A value the instinct cannot run without never came: the words go to the web.
        let format: Instinct = spec.arguments.missingRequired(in: arguments).isEmpty ? decision.instinct : .webResults
        let context = InstinctContext(
            query: query,
            decision: decision,
            opened: opened,
            canAnswer: canAnswer,
            thread: decision.continuesThread ? (current?.thread ?? []) : [],
            earlier: earlier,
            arguments: format == decision.instinct ? arguments : [:],
            extraction: extraction,
            reading: reading
        )
        return EngineResult(query: query, decision: decision, extraction: extraction, reading: reading, instinct: instinct(for: format), context: context, inferred: inferred)
    }

    func instinct(for format: Instinct) -> any InstinctRunner {
        // The registry covers every format; `InstinctRegistry.all()` asserts it.
        instincts.first { $0.spec.instinct == format }!
    }
}

/// The instinct to run and what it runs on; the decision behind it for the
/// log; how the reading and the extractor went; and a fact the words stated
/// on the way, for the session to keep. Or a query for the executor to plan.
struct EngineResult {
    /// The words that ran: the typed query, or the reading's when it rewrote them.
    var query: String
    var decision: Pick
    var extraction: ExtractionSummary? = nil
    var reading: ReadingSummary? = nil
    /// The instinct to run, with what it needs; nil for a query to plan.
    var instinct: (any InstinctRunner)? = nil
    var context: InstinctContext? = nil
    var inferred: Fact? = nil
    /// The query goes to advanced reasoning, with these exchanges as what it depends on.
    var reasoning = false
    var chained: [Exchange] = []
}

extension BrowserSession {
    /// Jev when a key is configured; without one, addresses load and the
    /// rest is web results. Gemini reads beside Jev, reads a pick's
    /// free-form values and plans, when its key is configured.
    static func makeEngine() -> Engine {
        let router = Secrets.typeSafeAPIKey.map { Picker(client: JevClient(apiKey: $0)) }
        let reader = Secrets.geminiAPIKey.map { QueryReader(client: GeminiClient(apiKey: $0)) }
        let extractor = Secrets.geminiAPIKey.map { ValueExtractor(client: GeminiClient(apiKey: $0)) }
        let planner = Secrets.geminiAPIKey.map { Planner(client: GeminiClient(apiKey: $0, model: Planner.model, totalTimeout: ReasoningPolicy.roundTimeout)) }
        return Engine(router: router, reader: reader, extractor: extractor, planner: planner, canAnswer: Secrets.geminiAPIKey != nil)
    }

    /// Brave's web search for the sites an unknown name might mean, when a
    /// key is configured; nil shows the Google results page for the name.
    static func makeSiteSearch() -> SiteSearch? {
        Secrets.braveAPIKey.map { SiteSearch(apiKey: $0) }
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
