import Foundation

/// A routing decision and what the app will act on for it: the device's own
/// answer text when a local rule fired, and what the post-routing parsers
/// make of the query for the format chosen, so `route`, the eval and the
/// log agree on the term searched, the subject pictured or the site named.
public struct RouteOutcome: Equatable, Sendable {
    public var decision: RouteDecision
    /// The one-line answer the device computed (the time rule); nil otherwise.
    public var localText: String?
    /// What goes into the search box: for web results, the query with its
    /// search verb gone (`SearchQuery.term(for:)`); for videos, the query
    /// with the asking gone (`VideoQuery.term(for:)`). Nil otherwise; an
    /// address loads as typed.
    public var searchTerm: String?
    /// What Wikipedia is asked for on an image pick (`ImageQuery.subject(for:)`).
    public var imageSubject: String?
    /// The name looked up in the site book on a site pick (`SiteQuery.parse`).
    public var siteName: String?
    /// What the answer model is asked on a narrative or one-line pick: the
    /// query, or the question after an explicit ask (`AnswerQuery`).
    public var question: String?

    /// `opened` is the site on screen, if the app opened one by name: a
    /// decision that rejects it names that site again, whatever was typed.
    public init(query: String, decision: RouteDecision, localText: String? = nil, opened: OpenedSite? = nil) {
        self.decision = decision
        self.localText = localText
        switch decision.format {
        case .webResults:
            searchTerm = decision.source == .directURL ? nil : SearchQuery.term(for: query)
        case .image:
            imageSubject = ImageQuery.subject(for: query)
        case .video:
            searchTerm = VideoQuery.term(for: query)
        case .site:
            if decision.rejectsSite, let opened {
                siteName = opened.name
            } else {
                siteName = SiteQuery.parse(query)?.name ?? query
            }
        case .narrative, .oneLine:
            question = AnswerQuery.question(for: query)
        case .map, .stock, .recall:
            break
        }
    }
}

/// The device's rules before any model, in the order the app applies them
/// (`InstinctSpec.deviceRuleOrder`): a question `LocalAnswers` can answer
/// becomes a one-line card, a question handed to the model by name ("ask
/// AI ...") is a narrative, an opener and a site name the book knows opens
/// the site, and a verb that only ever means "search" is web results for
/// the term. Nil means no rule fired and the query goes on to Jev.
///
/// Each rule is the `recognise` grammar of the instinct it decides for, so
/// the app, the report CLI and the eval run the same code. An address is
/// not a rule here: the engine checks it after these, and so does the eval.
public enum DeviceRouting {
    public static let askRule = "ask"
    public static let siteRule = "site"
    public static let searchRule = "search"

    /// `canAnswer` is false without a Gemini key, which skips the ask rule.
    public static func decide(
        _ query: String,
        now: Date = .now,
        locale: Locale = .current,
        homeZone: TimeZone = .current,
        book: SiteBook,
        canAnswer: Bool = true
    ) -> RouteOutcome? {
        let context = RecogniseContext(now: now, locale: locale, homeZone: homeZone, book: book, canAnswer: canAnswer)
        for format in InstinctSpec.deviceRuleOrder {
            guard let hit = InstinctSpec.spec(for: format).recognise?(query, context) else { continue }
            return RouteOutcome(query: query, decision: .local(hit.rule, format: format), localText: hit.arguments["text"])
        }
        return nil
    }
}
