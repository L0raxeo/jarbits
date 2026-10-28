import Foundation
import Engine

/// The reading beside the Jev request: one small Gemini call that returns
/// the request with its substance isolated ("Which oh can you pull up
/// youtube?" → "can you pull up youtube?") and what it is about ("youtube"),
/// with anything the words pointed back at folded in ("pictures of it" after
/// a Brazil page → "Brazil"). The engine sends the typed words to Jev at the
/// same moment; a reading whose substance differs sends Jev the read words
/// again and that pick wins; the subject fills the picked instinct's object
/// field, so no grammar reads the words and the extractor is asked only
/// for a field beyond that. Built on the same whole-body call that reads
/// values, with its own schema and instruction.
public struct QueryReader: Sendable {
    public static let model = GeminiClient.defaultModel
    /// A query waits for the slower of Jev and this call, so the cap is
    /// what a query may lose to it; past it the typed words run with no
    /// subject. The first real calls took 0.97 and 1.38 s (2026-10-27).
    public static let timeout: Duration = .seconds(2)
    public static let maxOutputTokens = 120
    /// The newest exchanges the reading sees, so "it" and "that" resolve.
    public static let exchangesGiven = 3

    public static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "the request with its substance isolated; exactly the request when there is nothing to drop"],
            "subject": ["type": ["string", "null"], "description": "what the request is about, in the words used, standing on its own; null when it is about nothing in particular"],
        ],
        "required": ["query"],
        "additionalProperties": false,
    ]

    public static let system = """
        You read a request made to a phone's browser, usually dictated. Reply with JSON matching the schema and nothing else.
        query: the request with its substance isolated. Drop dictation noise, interjections, fillers, false starts and repeated words ("oh", "um", "wait no", a stray word the microphone added before the sentence). Keep every word that carries meaning, the person's own wording and language, names, numbers and addresses. Fix nothing else, never answer, never add. A request with nothing to drop comes back exactly as it is.
        subject: the thing the request is about, named bare, with none of the asking around it: the thing to search for, picture, open, watch, keep in mind, forget or bring back, or the place whose time is asked. "youtube", not "pull up youtube"; "Tokyo", not "the time in Tokyo"; "Brasília", not "pictures of Brasília"; "I'm vegetarian" for a fact to keep. Resolve "it", "that", "there" and the like against the earlier exchanges, so the subject stands on its own. Null when the request is about nothing in particular, such as the time here, a greeting, or a question with no one thing in it.
        Earlier exchanges of the session may come before the request, oldest first, and today's date.
        """

    public var extractor: ValueExtractor

    public init(client: GeminiClient, timeout: Duration = QueryReader.timeout) {
        extractor = ValueExtractor(client: client, timeout: timeout)
    }

    public var timeout: Duration { extractor.timeout }

    /// The request the app sends, for the report and the CLI.
    public static func request(query: String, exchanges: [Exchange] = [], now: Date = .now, model: String = model) -> InteractionRequest {
        ValueExtractor.request(query: query, exchanges: Array(exchanges.suffix(exchangesGiven)), schema: schema, instructions: system, model: model, maxOutputTokens: maxOutputTokens, now: now)
    }

    /// One call within the timeout; never throws. `.rewritten` only when
    /// the substance differs (`Substance.differs`).
    public func read(_ query: String, exchanges: [Exchange] = [], now: Date = .now) async -> ReadingSummary {
        let verdict = await extractor.extract(query: query, exchanges: Array(exchanges.suffix(Self.exchangesGiven)), schema: Self.schema, instructions: Self.system, maxOutputTokens: Self.maxOutputTokens, now: now)
        switch verdict {
        case let .values(values, summary):
            let text = values["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let subject = values["subject"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return ReadingSummary(original: query, model: summary.model, latencyMs: summary.latencyMs, usage: summary.usage, outcome: .failed("no query"))
            }
            let changed = Substance.differs(query, text)
            return ReadingSummary(original: query, query: text, subject: subject?.isEmpty == false ? subject : nil, model: summary.model, latencyMs: summary.latencyMs, usage: summary.usage, outcome: changed ? .rewritten : .unchanged)
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
