import Foundation
import Engine

/// The line that closes a plan that could not finish: the device knows
/// what was tried and why it stopped, and hands those facts, and nothing
/// else, to the cheap model to word in Jarbits's voice for the user: what
/// it tried in plain words, why it did not work out, and what they could
/// do instead. A line the planner already said (its promise to keep
/// checking, its reason) is listed so the closing adds only what is new.
/// A miss (no key, no credit, a slow reply) leaves the fixed lines the
/// bubble has always had (2026-10-31). A long answer that brought nothing is
/// closed the same way, and a plan that partly worked gets a line about what
/// did not happen, or none when all of it did (2026-11-02).
public struct Closing: Sendable {
    public static let model = GeminiClient.defaultModel
    public static let timeout: Duration = .seconds(6)
    public static let maxOutputTokens = 120
    /// A reading of the request, thing by thing, comes before the line.
    public static let partlyMaxOutputTokens = 500

    public var client: GeminiClient
    public var timeout: Duration

    public init(client: GeminiClient, timeout: Duration = Closing.timeout) {
        self.client = client
        self.timeout = timeout
    }

    /// Why the plan stopped, as the device knows it.
    public enum Reason: String, Sendable {
        case budget = "I had looked for as long as I allow myself and stopped before settling it"
        case failed = "every step failed"
        case nothing = "nothing came of it"
        /// The plan showed or did something, and a step did not work or the
        /// plan stopped short: the line is about what did not happen.
        case partly = "some of it got done, and a step did not work or I stopped short"
    }

    /// What the model made of a plan that partly worked.
    public enum Remainder: Sendable, Equatable {
        /// What did not happen, to tell the user.
        case line(String)
        /// Nothing to add: all of it happened after all, or it has been said.
        case nothing
        /// No usable reply.
        case missed
    }

    public static var schema: JSONValue {
        [
            "type": "object",
            "properties": [
                "line": ["type": "string", "description": "one short line to the user, in the assistant's own voice"],
            ],
            "required": ["line"],
            "additionalProperties": false,
        ]
    }

    /// A plan that partly worked is read thing by thing, so whether anything
    /// is left is the model's reading of the request and the line follows it:
    /// asked only for a line, it wrote one every time, about nothing.
    public static var partlySchema: JSONValue {
        [
            "type": "object",
            "properties": [
                "things": [
                    "type": "array",
                    "description": "each thing the request asks for",
                    "items": [
                        "type": "object",
                        "properties": [
                            "thing": ["type": "string"],
                            "got": ["type": "boolean"],
                            "already_said": ["type": "boolean"],
                        ],
                        "required": ["thing", "got", "already_said"],
                        "additionalProperties": false,
                    ],
                ],
                "line": ["type": "string", "description": "one short line to the user about what is left, or empty"],
            ],
            "required": ["things", "line"],
            "additionalProperties": false,
        ]
    }

    public static var system: String { system(Persona()) }

    public static func system(_ persona: Persona, reason: Reason = .nothing) -> String {
        let task = reason == .partly ? """
        \(persona.user.capitalizedFirst) asked you for something and part of it may not have happened; what did happen is already in front of \(persona.user). From the facts below and nothing else, list under things each thing the request asks for, in the request's own terms, never a step you took. A step that did not work is only one way you tried: if any step got the thing, got is true. already_said is true when a line you already said to \(persona.user) covers it. Then line is about the things with got false and already_said false, if any: one short line to \(persona.user), in your own voice (you for them, I for yourself): that thing, in plain words, and what they could do instead when you know of something that would ("I couldn't send Noah that text, sir. You'll have to do that one yourself."). Speak only of what is left, never of what got done. If nothing is left, line is empty.
        """ : """
        \(persona.user.capitalizedFirst) asked you for something and you could not finish it. From the facts below and nothing else, write one short line to \(persona.user), in your own voice (you for them, I for yourself): what you tried, in plain words, why it did not work out, and what they could do instead when you know of something that would (Maps for a distance, a site or a call for a booking). If a line you already said to them is listed, do not repeat it: add only what is new, or say that you kept looking and found nothing more.
        """
        return persona.speakerLine + "\n\n" + Voice.background(persona) + "\n" + Voice.guide(persona) + "\n" + Voice.dividerVoiceOnly + "\n\nTruth (never bent): " + task + " " + """
        Two sentences at most. Say only what happened here: never that you did something not listed as tried, and never that you are unable to do a kind of thing. The reason listed is the only cause you know: never name another, such as the connection, a timeout or a site being down. The looking is over: never promise to look again or to do anything later. Never a tool name, a handle, a count of steps or rounds, or anything technical: say what a person would say. Reply with JSON matching the schema and nothing else.
        """
    }

    /// The facts: the request, each step in plain words, the reason, and
    /// what was already said.
    public static func input(query: String, steps: [EngineSummary.Step], reason: Reason, said: [String], persona: Persona = Persona()) -> String {
        var lines = ["Request: \(query)"]
        let tried = steps.compactMap { describe($0, persona: persona) }
        lines.append(tried.isEmpty ? "Tried: nothing got started" : "Tried, in order:")
        lines += tried.map { "- " + $0 }
        lines.append("Why it stopped: \(reason.rawValue)")
        if !said.isEmpty {
            lines.append("Already said to \(persona.user):")
            lines += said.map { "- " + $0 }
        }
        return lines.joined(separator: "\n")
    }

    /// One step as a person would say it; nil for a step that is not worth a word.
    static func describe(_ step: EngineSummary.Step, persona: Persona = Persona()) -> String? {
        let arguments = step.arguments.objectValue ?? [:]
        let query = arguments["query"]?.stringValue ?? arguments["text"]?.stringValue ?? ""
        let what: String
        switch step.name {
        case "web_results", "site": what = query.isEmpty ? "searched the web" : "searched the web for \"\(query)\""
        case "map": what = query.isEmpty ? "looked at a map" : "looked at a map for \"\(query)\""
        case "look": what = "read the page"
        case "narrative", "one_line": what = query.isEmpty ? "tried to answer" : "tried to answer \"\(query)\""
        case "say": return nil
        case "ask": what = "asked \(persona.user) a question"
        case "open": what = "opened something"
        case "done": return nil
        case "notebook": what = "went to the notebook"
        case "recall": what = "looked through what I have open"
        case "facts": what = "looked through what I know about \(persona.user)"
        default: what = query.isEmpty ? "tried \(step.name.replacingOccurrences(of: "_", with: " "))" : "tried \"\(query)\""
        }
        let outcome: String
        switch step.outcome {
        case "shown", "read", "ran", "asked", "done", "already ran": outcome = "and got something"
        case "looked: no reply": outcome = "and got nothing usable"
        case let text where text.hasPrefix("looked"): outcome = "and read it"
        case let text where text.hasPrefix("failed"): outcome = "and it did not work"
        case "declined", "dismissed": outcome = "and \(persona.user) said no"
        default: outcome = "and got nothing usable"
        }
        return "\(what) \(outcome)"
    }

    /// What the planner said to the user on the way: its say steps' text.
    public static func said(in steps: [EngineSummary.Step]) -> [String] {
        steps.compactMap { step in
            guard step.name == "say", let text = step.arguments.objectValue?["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
    }

    public static func request(query: String, steps: [EngineSummary.Step], reason: Reason, persona: Persona = Persona(), model: String = model) -> InteractionRequest {
        InteractionRequest(
            model: model,
            systemInstruction: system(persona, reason: reason),
            input: input(query: query, steps: steps, reason: reason, said: said(in: steps), persona: persona),
            maxOutputTokens: reason == .partly ? partlyMaxOutputTokens : maxOutputTokens,
            stream: false,
            outputSchema: reason == .partly ? partlySchema : schema
        )
    }

    /// The line in a reply's text, or nil when there is none.
    public static func line(in text: String) -> String? {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)), let object = try? JSONValue(any: parsed).objectValue,
              let line = object["line"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
        return line
    }

    /// What a reply's text says about a plan that partly worked: the line
    /// stands only when a thing is left, by the reply's own reading.
    public static func remainder(in text: String) -> Remainder {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)), let object = try? JSONValue(any: parsed).objectValue,
              let things = object["things"]?.arrayValue?.compactMap(\.objectValue) else { return .missed }
        let left = things.contains { $0["got"]?.boolValue == false && $0["already_said"]?.boolValue != true }
        guard left else { return .nothing }
        return line(in: text).map(Remainder.line) ?? .missed
    }

    /// The record of a long or one-line answer that brought nothing, for
    /// `line`: the one step there was.
    public static func failedAnswer(query: String, format: Instinct) -> [EngineSummary.Step] {
        [EngineSummary.Step(name: format == .oneLine ? "one_line" : "narrative", arguments: ["query": .string(query)], outcome: "failed: nothing came back", latencyMs: 0)]
    }

    /// What did not happen in a plan that partly worked: one call within `timeout`.
    public func remainder(query: String, steps: [EngineSummary.Step], persona: Persona = Persona()) async -> (remainder: Remainder, latencyMs: Int) {
        let clock = ContinuousClock()
        let start = clock.now
        let request = Self.request(query: query, steps: steps, reason: .partly, persona: persona, model: client.model)
        guard let interaction = try? await client.interact(request, timeout: timeout), interaction.usable else {
            return (.missed, Int((clock.now - start) / .milliseconds(1)))
        }
        return (Self.remainder(in: interaction.text), Int((clock.now - start) / .milliseconds(1)))
    }

    /// One call within `timeout`; nil on any miss, so the fixed line stands.
    public func line(query: String, steps: [EngineSummary.Step], reason: Reason, persona: Persona = Persona()) async -> (line: String?, latencyMs: Int) {
        let clock = ContinuousClock()
        let start = clock.now
        let request = Self.request(query: query, steps: steps, reason: reason, persona: persona, model: client.model)
        guard let interaction = try? await client.interact(request, timeout: timeout), interaction.usable else {
            return (nil, Int((clock.now - start) / .milliseconds(1)))
        }
        return (Self.line(in: interaction.text), Int((clock.now - start) / .milliseconds(1)))
    }
}
