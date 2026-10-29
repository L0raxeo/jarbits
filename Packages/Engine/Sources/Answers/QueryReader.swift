import Foundation
import Engine

/// The reading beside the Jev request: one small Gemini call that returns
/// the request with its substance isolated ("Which oh can you pull up
/// youtube?" → "can you pull up youtube?"), with anything the words pointed
/// back at folded in ("pictures of it" after a Brazil page → "pictures of
/// Brazil"). The engine sends the typed words to Jev at the same moment; a
/// reading whose substance differs sends Jev the read words again and that
/// pick wins; the read words are what the instinct and the extractor get.
/// Built on the same whole-body call that reads values, with its own schema
/// and instruction.
public struct QueryReader: Sendable {
    public static let model = GeminiClient.defaultModel
    /// A query waits for the slower of Jev and this call, so the cap is
    /// what a query may lose to it; past it the typed words run, and a
    /// chained search goes out unresolved. From the Mac the
    /// call takes 1.0 to 1.4 s (2026-10-27); a phone's network is slower,
    /// and a miss here costs more than a wait, so the cap is twice that.
    /// The console prints each call's time; set this from the phone's.
    public static let timeout: Duration = .seconds(4)
    public static let maxOutputTokens = 120
    /// The newest exchanges the reading sees, so "it" and "that" resolve.
    public static let exchangesGiven = 3

    public static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "the request standing on its own; exactly the request when there is nothing to drop and nothing to fold in"],
        ],
        "required": ["query"],
        "additionalProperties": false,
    ]

    /// The nameless form, for the CLI and tests; the app sends `system(_:)`.
    public static var system: String { system(Persona()) }

    public static func system(_ persona: Persona) -> String {
        persona.readerLine + "\n" + """
        You read a request \(persona.user) made to you, usually dictated. Reply with JSON matching the schema and nothing else.
        query: the request, standing on its own, whole. The only words to drop are ones that carry nothing: dictation noise, fillers, false starts and repeated words. Everything else stays, in the person's own wording and language: names, numbers, addresses, and above all how they asked for it to be done. "google", "look up", "search", "ask AI", "pull up", "show me pictures of", "remember", "bring back" name what they want done and are the most important words in the request; a request that asks for a search comes back still asking for a search, never turned into the bare question. Polite framing around such a word ("can you google X" → "google X") is the frame, not the word. A request that leans on the earlier exchanges comes back complete, with what they make clear folded in, so it can be read with nothing else in view. \(Screen.rule) "how much is this" over a page showing one thing names that thing; "google chocolate milk" over any page stays as it is. Never answer, never add anything the request, the exchanges and the screen do not say. A request with nothing to drop and nothing to fold in comes back exactly as it is.
        Earlier exchanges of the session may come before the request, oldest first, then today's date, then what is on the screen.
        """
    }

    public var extractor: ValueExtractor

    public init(client: GeminiClient, timeout: Duration = QueryReader.timeout) {
        extractor = ValueExtractor(client: client, timeout: timeout)
    }

    public var timeout: Duration { extractor.timeout }

    /// The request the app sends, for the report and the CLI.
    public static func request(query: String, exchanges: [Exchange] = [], now: Date = .now, model: String = model, persona: Persona = Persona(), screen: Screen? = nil) -> InteractionRequest {
        ValueExtractor.request(query: query, exchanges: Array(exchanges.suffix(exchangesGiven)), schema: schema, instructions: system(persona), model: model, maxOutputTokens: maxOutputTokens, now: now, screen: screen)
    }

    /// One call within the timeout; never throws. `.rewritten` only when
    /// the substance differs (`Substance.differs`). `screen` is what the
    /// user sees as they ask: the selection and the visible text go.
    public func read(_ query: String, exchanges: [Exchange] = [], now: Date = .now, persona: Persona = Persona(), screen: Screen? = nil) async -> ReadingSummary {
        let verdict = await extractor.extract(query: query, exchanges: Array(exchanges.suffix(Self.exchangesGiven)), schema: Self.schema, instructions: Self.system(persona), maxOutputTokens: Self.maxOutputTokens, now: now, screen: screen)
        switch verdict {
        case let .values(values, summary):
            let text = values["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                return ReadingSummary(original: query, model: summary.model, latencyMs: summary.latencyMs, usage: summary.usage, outcome: .failed("no query"))
            }
            let changed = Substance.differs(query, text)
            return ReadingSummary(original: query, query: text, model: summary.model, latencyMs: summary.latencyMs, usage: summary.usage, outcome: changed ? .rewritten : .unchanged)
        case let .failed(summary):
            let reason: String
            switch summary.outcome {
            case let .failed(text): reason = text
            case .empty, .extracted: reason = "no query"
            }
            return ReadingSummary(original: query, model: summary.model, latencyMs: summary.latencyMs, usage: summary.usage, outcome: .failed(reason))
        }
    }
}
