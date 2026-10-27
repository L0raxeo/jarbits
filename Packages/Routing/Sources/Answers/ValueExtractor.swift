import Foundation
import Routing

/// Reads an instinct's free-form values out of the words with one small
/// Gemini call: the query, the exchanges it depends on, and a JSON schema
/// of the fields wanted; back comes JSON matching it, or nothing. Jev
/// cannot write a value down, so this is the one place a model does on the
/// direct path; a closed-set value is Jev's question instead. The engine
/// asks only when the pick declares a field its grammar did not read, and
/// shows web results when nothing usable comes back.
public struct ValueExtractor: Sendable {
    public static let model = GeminiClient.defaultModel
    /// A whole-body reply waits for the whole generation, not a first byte:
    /// the first real call took 1.05 s for two values (2026-10-27), so one
    /// second was a miss. A slower reply than this is a miss, logged as
    /// such, and the log argues for more or less.
    public static let timeout: Duration = .seconds(2)
    public static let maxOutputTokens = 120

    public static let system = """
        You read values out of a request made to a phone's browser. Reply with JSON matching the schema and nothing else.
        A value is what the request says: a number as a number, words as the words used. Anything the request does not state is null.
        Never guess, never add fields. Earlier exchanges of the session may come before the request, oldest first; "it", "that" and the like resolve against them.
        """

    public var client: GeminiClient
    /// The budget for one call; `Self.timeout` unless a test shortens it.
    public var timeout: Duration

    public init(client: GeminiClient, timeout: Duration = ValueExtractor.timeout) {
        self.client = client
        self.timeout = timeout
    }

    /// "Earlier: …" lines for the chained exchanges, then the request.
    public static func input(query: String, exchanges: [Exchange]) -> String {
        var lines = exchanges.map { "Earlier: " + AnswerPrompt.describe($0) }
        lines.append("Request: \(query)")
        return lines.joined(separator: "\n")
    }

    /// The schema and the instruction that distil a lasting fact about the
    /// user out of a query that states one on the way to asking something
    /// else ("I'm allergic to peanuts, what can I snack on").
    public static let factSchema: JSONValue = [
        "type": "object",
        "properties": ["fact": ["type": ["string", "null"], "description": "the lasting fact about the user, in one short sentence in their own voice; null when the request states none"]],
        "required": [],
        "additionalProperties": false,
    ]

    public static let factSystem = """
        You note what a request made to a phone's browser says about the person making it. Reply with JSON matching the schema and nothing else.
        A fact is something lasting about them, a preference, an allergy, a name, where they live, that will still be true next week and could shape a later answer; state it in one short sentence in their own voice ("I'm allergic to peanuts"). Something true only now, a fact about the world, or a question with nothing lasting in it is null.
        Earlier exchanges of the session may come before the request, oldest first.
        """

    public static func request(query: String, exchanges: [Exchange], schema: JSONValue, instructions: String = system, model: String = model) -> InteractionRequest {
        InteractionRequest(
            model: model,
            systemInstruction: instructions,
            input: input(query: query, exchanges: exchanges),
            maxOutputTokens: maxOutputTokens,
            stream: false,
            outputSchema: schema
        )
    }

    public enum Verdict: Sendable, Equatable {
        /// The values read, nulls gone, and how it went.
        case values([String: JSONValue], ExtractionSummary)
        /// Nothing usable: the call failed, timed out, or read no value.
        case failed(ExtractionSummary)
    }

    /// One call within `timeout`; never throws. `instructions` is the
    /// system instruction, `system` unless a different reading is wanted.
    public func extract(query: String, exchanges: [Exchange], schema: JSONValue, instructions: String = system) async -> Verdict {
        let clock = ContinuousClock()
        let start = clock.now
        func summary(_ outcome: ExtractionSummary.Outcome, fields: [String] = [], usage: AnswerUsage? = nil) -> ExtractionSummary {
            ExtractionSummary(model: client.model, latencyMs: Int((clock.now - start) / .milliseconds(1)), usage: usage, fields: fields, outcome: outcome)
        }
        let request = Self.request(query: query, exchanges: exchanges, schema: schema, instructions: instructions, model: client.model)
        let interaction: Interaction
        do {
            interaction = try await client.interact(request, timeout: timeout)
        } catch {
            return .failed(summary(.failed(error.summary)))
        }
        guard interaction.usable else {
            return .failed(summary(.failed("status \(interaction.status)"), usage: interaction.usage))
        }
        let text = interaction.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)), let object = try? JSONValue(any: parsed).objectValue else {
            return .failed(summary(.failed("not an object: \(text.prefix(80))"), usage: interaction.usage))
        }
        let values = object.filter { !$0.value.isNull }
        guard !values.isEmpty else {
            return .failed(summary(.empty, usage: interaction.usage))
        }
        return .values(values, summary(.extracted, fields: values.keys.sorted(), usage: interaction.usage))
    }

    /// The lasting fact a query states on the way to something else, in one
    /// sentence; nil when the model found none or the call missed.
    public func distill(query: String, exchanges: [Exchange]) async -> (fact: String?, summary: ExtractionSummary) {
        switch await extract(query: query, exchanges: exchanges, schema: Self.factSchema, instructions: Self.factSystem) {
        case let .values(values, summary):
            let text = values["fact"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty == false ? text : nil, summary)
        case let .failed(summary):
            return (nil, summary)
        }
    }
}
