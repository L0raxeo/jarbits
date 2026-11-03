import Foundation
import Engine

/// The device's check of what he claims against what he did: an answer to a
/// question about his own actions (what he did, said, changed, read or
/// showed) goes to the cheap model beside the record, and comes back as a
/// verdict: it agrees, or it contradicts the record and here is the
/// correction, in his voice. Asked once per answer, while the answer is
/// still coming when it can be, so he can cut himself off and put it
/// right in front of the user rather than let a wrong claim stand. A miss
/// leaves the answer as it is: the record was in the answer's own prompt,
/// so the check is a second look, never the only one.
public struct Checker: Sendable {
    public static let model = GeminiClient.defaultModel
    public static let timeout: Duration = .seconds(6)
    public static let maxOutputTokens = 200

    /// How a caught contradiction is shown.
    public enum Presentation: Sendable, Equatable {
        /// The words already out stay on screen, cut off where they are,
        /// and the correction follows under them: what a person does.
        case interrupt
        /// The answer is swapped for the correction, as if never said.
        case replace
    }

    public enum Verdict: Sendable, Equatable {
        /// The answer agrees with the record.
        case agrees
        /// It does not; this is what to say instead.
        case contradicts(String)
        /// No usable reply within the time.
        case missed
    }

    public var client: GeminiClient
    public var timeout: Duration

    public init(client: GeminiClient, timeout: Duration = Checker.timeout) {
        self.client = client
        self.timeout = timeout
    }

    public static var schema: JSONValue {
        [
            "type": "object",
            "properties": [
                "contradicts": ["type": "boolean", "description": "true only when the answer claims or denies one of your own actions against the record"],
                "correction": ["type": "string", "description": "when contradicts: one or two short sentences to the user, in the assistant's own voice, owning the mistake and saying what the record shows; otherwise empty"],
            ],
            "required": ["contradicts", "correction"],
            "additionalProperties": false,
        ]
    }

    public static var system: String { system(Persona()) }

    public static func system(_ persona: Persona) -> String {
        persona.speakerLine + "\n\n" + Voice.background(persona) + "\n" + Voice.guide(persona) + "\n" + Voice.dividerVoiceOnly + "\n\nTruth (never bent): " + """
        You are checking an answer you are giving \(persona.user), or have just given, against the record of your own actions. \(Done.rule(Done.answerHeading)) Read the answer against that block and nothing else. contradicts is true only when the answer says you did, said, changed, read or showed something the block does not list, or denies something it lists, or says you cannot do or find something the block shows you did or found. An answer about the world, about \(persona.user), or about anything the block does not bear on is never a contradiction, however wrong it might be: that is not what you are checking. Neither is an answer still being written that has not yet got to the point. When contradicts is true, correction is one or two short sentences to \(persona.user), in your own voice (you for them, I for yourself): own the mistake in a few words, then say what the record shows, with its time where that helps ("A moment, sir. I was wrong: I did rewrite that note, at two o'clock, and took most of it out."). Never a tool name, a handle, or anything technical. When contradicts is false, correction is empty. Reply with JSON matching the schema and nothing else.
        """
    }

    /// The facts: the query, the answer so far or whole, and the record.
    public static func input(query: String, answer: String, unfinished: Bool, done: Done, persona: Persona = Persona()) -> String {
        var lines = ["Query: \(query)", "", unfinished ? "Your answer so far, still being written:" : "Your answer:", answer]
        if let block = done.block(heading: Done.answerHeading) {
            lines.append("")
            lines.append(block)
        } else {
            lines.append("")
            lines.append("\(Done.answerHeading): nothing.")
        }
        return lines.joined(separator: "\n")
    }

    public static func request(query: String, answer: String, unfinished: Bool, done: Done, persona: Persona = Persona(), model: String = model) -> InteractionRequest {
        InteractionRequest(
            model: model,
            systemInstruction: system(persona),
            input: input(query: query, answer: answer, unfinished: unfinished, done: done, persona: persona),
            maxOutputTokens: maxOutputTokens,
            stream: false,
            outputSchema: schema
        )
    }

    /// The verdict in a reply's text; missed when it is not one.
    public static func verdict(in text: String) -> Verdict {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)), let object = try? JSONValue(any: parsed).objectValue,
              let contradicts = object["contradicts"]?.boolValue else { return .missed }
        guard contradicts else { return .agrees }
        guard let correction = object["correction"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !correction.isEmpty else { return .missed }
        return .contradicts(correction)
    }

    /// One call within `timeout`; never throws.
    public func check(query: String, answer: String, unfinished: Bool, done: Done, persona: Persona = Persona()) async -> (verdict: Verdict, latencyMs: Int) {
        let clock = ContinuousClock()
        let start = clock.now
        let request = Self.request(query: query, answer: answer, unfinished: unfinished, done: done, persona: persona, model: client.model)
        guard let interaction = try? await client.interact(request, timeout: timeout), interaction.usable else {
            return (.missed, Int((clock.now - start) / .milliseconds(1)))
        }
        return (Self.verdict(in: interaction.text), Int((clock.now - start) / .milliseconds(1)))
    }
}
