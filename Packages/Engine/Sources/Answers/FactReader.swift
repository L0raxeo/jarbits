import Foundation
import Engine

/// Reads every lasting personal fact a request states, beside the query
/// and whatever becomes of it: one small Gemini call that sees the words,
/// the last few exchanges, and the facts Jarbits already holds, numbered,
/// and returns a list. Each fact found is `new`, a restatement of a known
/// one (`same`, with its number: refreshed, no mark), or a change to one
/// (`changed`, with its number: the old words replaced and kept as
/// history). The reader interprets; the device writes what it said.
/// Nothing waits for it: the reply comes when it comes, and the facts
/// land in the store when they land (2026-10-30).
public struct FactReader: Sendable {
    public static let model = GeminiClient.defaultModel
    /// In the background, so there is room; a miss is logged, never shown.
    public static let timeout: Duration = .seconds(8)
    public static let maxOutputTokens = 400
    /// The exchanges the reader sees before the request: the newest few,
    /// for what "she" or "there" means.
    public static let exchangesGiven = 5

    /// One fact the reader found, and how it stands to what was known.
    public struct Finding: Equatable, Sendable {
        public enum Kind: String, Sendable, CaseIterable {
            case new, same, changed
        }

        public var text: String
        public var kind: Kind
        /// The number of the known fact this restates or changes, as the
        /// input numbered them (1-based); nil for a new fact.
        public var of: Int?

        public init(text: String, kind: Kind, of: Int? = nil) {
            self.text = text
            self.kind = kind
            self.of = of
        }
    }

    public var client: GeminiClient
    public var timeout: Duration

    public init(client: GeminiClient, timeout: Duration = FactReader.timeout) {
        self.client = client
        self.timeout = timeout
    }

    public static var schema: JSONValue { schema(Persona()) }

    public static func schema(_ persona: Persona) -> JSONValue {
        [
            "type": "object",
            "properties": [
                "facts": [
                    "type": "array",
                    "description": .string("every lasting personal fact the request states, as \(Persona.assistant) notes it; empty when it states none"),
                    "items": [
                        "type": "object",
                        "properties": [
                            "text": ["type": "string", "description": .string("the fact in one short sentence, naming \(persona.user)")],
                            "kind": ["type": "string", "enum": ["new", "same", "changed"], "description": "new: not among the known facts; same: a known fact in other words; changed: a known fact this replaces"],
                            "of": ["type": ["integer", "null"], "description": "the number of the known fact this is the same as or changes; null for a new fact"],
                        ],
                        "required": ["text", "kind"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["facts"],
            "additionalProperties": false,
        ]
    }

    public static var system: String { system(Persona()) }

    public static func system(_ persona: Persona) -> String {
        persona.identityLine + "\n" + """
        You note every lasting personal fact a request \(persona.user) made to you states. Reply with JSON matching the schema and nothing else.
        A fact is something lasting about \(persona.users) own life: who they are, who and what is around them, how they live. An allergy, a name, where they live, their job, a coworker, their mother's age, a standing preference ("I prefer window seats"). It stays true whatever \(persona.user) happens to be working on, and could shape a later answer about anything. A request may hold several: "my friend Noah declared himself vegan in middle school, then brought pepperoni pizza the next day" holds "\(persona.user.capitalizedFirst) has a friend named Noah" and "\(persona.users) friend Noah declared himself vegan in middle school and brought pepperoni pizza to school the next day". State each in one short sentence as you would note it, from your own point of view: \(persona.user) by name, never "I" or "my" for them, and whoever or whatever else the words name kept as the words relate them to \(persona.user) ("\(persona.users) friend Noah is vegan", "\(persona.user.capitalizedFirst) is allergic to peanuts", "\(persona.users) mom Jasmine is 50 years old").
        The facts already known are numbered below. A fact the request states that is already there in other words is same, with that fact's number. A fact that changes or replaces one that is there ("Ana and I split up" after "\(persona.users) wife is Ana"; "I eat fish now" after "\(persona.user.capitalizedFirst) is vegetarian") is changed, with that fact's number and the new words. Anything else is new.
        Something true only now ("I'm hungry", "I'm at the airport"), a fact about the world with no one personal in it ("the capital of Peru is Lima"), a question with nothing lasting in it, or a request that points at something seen in this app ("remember that page", "that conversation about the Dyson") gives an empty list.
        A decision or detail inside something \(persona.user) is making or working on (a project, a note, a draft, a design: "I want my project represented by a robot rather than an animal", "make the logo blue", "the app should open on the map") is a fact about that work, not about \(persona.user), and gives nothing, whatever words carry it ("I want", "I've decided", "add to my notes that"). The work itself keeps it. The same request can still state a fact about \(persona.users) life, which is kept: "add to my project notes that my cofounder Maya wants a robot" gives "\(persona.user.capitalizedFirst) has a cofounder named Maya" and nothing about the robot; "add to my notes that my sister moved to Austin" gives "\(persona.users) sister moved to Austin".
        Earlier exchanges of the session may come before the request, oldest first; "she", "it" and "there" resolve against them.
        """
    }

    /// The exchanges as "Earlier:" lines, today's date, the known facts
    /// numbered, then the request.
    public static func input(query: String, exchanges: [Exchange], known: [String], now: Date? = nil) -> String {
        var lines = exchanges.map { "Earlier: " + AnswerPrompt.describe($0) }
        if let now { lines.append("Today: " + now.formatted(Date.FormatStyle(date: .complete, time: .shortened, locale: Locale(identifier: "en_US")))) }
        if known.isEmpty {
            lines.append("Known facts: none yet")
        } else {
            lines.append("Known facts:")
            for (index, fact) in known.enumerated() { lines.append("\(index + 1). \(fact)") }
        }
        lines.append("Request: \(query)")
        return lines.joined(separator: "\n")
    }

    public static func request(query: String, exchanges: [Exchange], known: [String], persona: Persona = Persona(), model: String = model, now: Date? = nil) -> InteractionRequest {
        InteractionRequest(
            model: model,
            systemInstruction: system(persona),
            input: input(query: query, exchanges: exchanges, known: known, now: now),
            maxOutputTokens: maxOutputTokens,
            stream: false,
            outputSchema: schema(persona)
        )
    }

    /// The findings in a reply's text: entries without words are dropped,
    /// and a same or changed entry whose number names no known fact is
    /// dropped too, since keeping it as new would invent one.
    public static func findings(in text: String, known: Int) -> [Finding]? {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)), let object = try? JSONValue(any: parsed).objectValue,
              let items = object["facts"]?.arrayValue else { return nil }
        return items.compactMap { item in
            guard let fields = item.objectValue,
                  let words = fields["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty,
                  let kind = fields["kind"]?.stringValue.flatMap(Finding.Kind.init(rawValue:)) else { return nil }
            let of = fields["of"]?.intValue
            if kind != .new {
                guard let of, of >= 1, of <= known else { return nil }
                return Finding(text: words, kind: kind, of: of)
            }
            return Finding(text: words, kind: .new)
        }
    }

    /// One call within `timeout`; never throws. An empty list is a reading
    /// that found nothing; a failed call is a reading that missed.
    public func read(query: String, exchanges: [Exchange], known: [String], persona: Persona = Persona(), now: Date? = nil) async -> (findings: [Finding], summary: ExtractionSummary) {
        let clock = ContinuousClock()
        let start = clock.now
        func summary(_ outcome: ExtractionSummary.Outcome, usage: AnswerUsage? = nil) -> ExtractionSummary {
            ExtractionSummary(model: client.model, latencyMs: Int((clock.now - start) / .milliseconds(1)), usage: usage, fields: ["facts"], outcome: outcome)
        }
        let request = Self.request(query: query, exchanges: Array(exchanges.suffix(Self.exchangesGiven)), known: known, persona: persona, model: client.model, now: now)
        let interaction: Interaction
        do {
            interaction = try await client.interact(request, timeout: timeout)
        } catch {
            return ([], summary(.failed(error.summary)))
        }
        guard interaction.usable else {
            return ([], summary(.failed("status \(interaction.status)"), usage: interaction.usage))
        }
        let text = interaction.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let found = Self.findings(in: text, known: known.count) else {
            return ([], summary(.failed("not a list: \(text.prefix(80))"), usage: interaction.usage))
        }
        return (found, summary(found.isEmpty ? .empty : .extracted, usage: interaction.usage))
    }
}
