import Foundation
import Routing

/// Advanced reasoning's one call shape: the request, its earlier
/// exchanges, the facts and the memories the words point at go to Gemini
/// with every instinct as a tool, and back come the calls to make. The
/// model's own words are never shown: it speaks through the narrative and
/// one-line instincts, with a query it writes, and asks through the sheet.
/// The app's executor runs the calls and brings their results back for
/// the next round; `store` is false, so every step is replayed each time.
public struct Planner: Sendable {
    /// The extractor's model and level, chosen 2026-10-27 after measuring
    /// `gemini-3.8-flash` on the first round of "remember I'm vegetarian,
    /// then suggest a dinner recipe" (13 tools, one fact, 2551 input
    /// tokens): it refuses `minimal` (HTTP 400, "THINKING_LEVEL_MINIMAL is
    /// not supported for this model"), and at `low` the round took
    /// 10974 ms and 961 thought tokens, $0.0056, past the round budget and
    /// three times the price agreed; the call itself was right (one
    /// `remember`, then wait). A plan is sequencing under explicit rules,
    /// so the Lite model does it at the Lite price; raise this constant if
    /// the log shows poor plans.
    public static let model = GeminiClient.defaultModel
    public static let thinkingLevel = "minimal"
    /// Room for the thoughts and a few calls with long queries; a call is
    /// under a hundred tokens, and nothing is paid for that is not produced.
    public static let maxOutputTokens = 1000

    /// The field every tool takes: what to run it on.
    public static let queryField = ArgumentSchema.Field(
        name: "query", kind: .text,
        description: "the words to run it on: complete and self-contained, with anything learned in earlier steps folded in"
    )

    /// The two tools the executor answers itself.
    public static let askTool = ToolDeclaration(
        name: "ask",
        description: "Put one short question to the user on a small sheet and get the answer back: to confirm, to choose, or to get a value the request leaves out. Give one to three options with the expected one first, or none for a line of text.",
        parameters: [
            "type": "object",
            "properties": [
                "question": ["type": "string", "description": "the question, in a line"],
                "options": ["type": "array", "items": ["type": "string"], "description": "one to three choices, the expected one first; leave out for a typed line"],
            ],
            "required": ["question"],
            "additionalProperties": false,
        ]
    )
    public static let doneTool = ToolDeclaration(
        name: "done",
        description: "Call once the request has been handled, or once nothing you can do would help.",
        parameters: ["type": "object", "properties": [:], "required": [], "additionalProperties": false]
    )

    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
    }

    /// Every instinct as a tool, in registry order, then `ask` and `done`.
    public static func tools(for registry: [InstinctSpec]) -> [ToolDeclaration] {
        registry.map { spec in
            let schema = ArgumentSchema(fields: [queryField] + spec.arguments.fields)
            return ToolDeclaration(name: spec.id, description: describe(spec), parameters: schema.jsonSchema())
        } + [askTool, doneTool]
    }

    static func describe(_ spec: InstinctSpec) -> String {
        var text = spec.criterion.what
        if !spec.criterion.notFor.isEmpty { text += " Not for: " + spec.criterion.notFor }
        text += spec.showsLayer ? " Puts its result on screen." : " Shows nothing; a mark says what was done."
        switch spec.sideEffects {
        case .paid: text += " Costs money; the device confirms it with the user first."
        case .destructive: text += spec.asksItself ? " Asks the user itself before acting." : " Cannot be undone; the device confirms it with the user first."
        case .none, .reversible: break
        }
        return text
    }

    public static func system(facts: [String], context: AnswerContext) -> String {
        var lines = [
            "You plan what a phone's browser does for a request. You never answer in text: nothing you write is shown to anyone. You act only by calling the tools below, and the device runs them.",
            "",
            "Rules:",
            "- To tell the user anything, call narrative or one_line with a complete, self-contained question in its query, with whatever you learned from earlier steps folded in; the device answers it. Never summarise a result yourself.",
            "- To confirm something, to choose, or to get a value the request leaves out, call ask; the answer comes back as the result.",
            "- A tool that costs money or cannot be undone is confirmed with the user by the device before it runs, not by you.",
            "- Show at most one thing, as the last step: \(InstinctSpec.all.filter(\.showsLayer).map(\.id).joined(separator: ", ")) each put a result on screen, and a second one would replace the first.",
            "- When an answer on the sheet is something lasting about the user, call remember with it next.",
            "- Call several tools in one turn only when none needs another's result; otherwise one at a time, and read the result before the next.",
            "- A step whose result says it ran is done: never call it again with the same arguments.",
            "- Call done when the request has been handled, or when nothing you can do would help.",
            "- Date and time: \(AnswerPrompt.dateText(context)). Locale: \(context.locale.identifier).",
            "",
            "What you know about the user (told earlier; let it shape what you do, never repeat it):",
        ]
        lines += facts.isEmpty ? ["- nothing yet"] : facts.map { "- " + $0 }
        return lines.joined(separator: "\n")
    }

    /// The request, the exchanges it depends on, and the memories the
    /// words point at, as the plan's first turn.
    public static func input(query: String, exchanges: [Exchange], memories: [MemoryRecord], now: Date, calendar: Calendar = .current) -> String {
        var lines = ["Request: \(query)"]
        if !exchanges.isEmpty {
            lines.append("")
            lines.append("Earlier in this session (oldest first):")
            lines += exchanges.map { "- " + AnswerPrompt.describe($0) }
        }
        if !memories.isEmpty {
            lines.append("")
            lines.append("Seen in this app before, that the request may mean (newest first):")
            lines += memories.map { record in
                let label = record.kind.label
                let article = "aeiou".contains(label.first ?? "x") ? "An" : "A"
                var line = "- \(article) \(label) from \(RecallRouting.when(record.date, now: now, calendar: calendar))"
                if let host = record.url?.host() { line += " (\(host))" }
                line += ": \"\(record.title)\""
                return line
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func request(bundle: PlanBundle, transcript: [InteractionStep], model: String = model) -> InteractionRequest {
        InteractionRequest(
            model: model,
            systemInstruction: system(facts: bundle.facts, context: bundle.context),
            input: "",
            maxOutputTokens: maxOutputTokens,
            thinkingLevel: thinkingLevel,
            stream: false,
            tools: bundle.tools,
            toolChoice: .any,
            transcript: transcript
        )
    }

    /// One round: the model's steps and the calls it asks for. Never throws.
    public func propose(_ bundle: PlanBundle, transcript: [InteractionStep], timeout: Duration = ReasoningPolicy.roundTimeout) async -> PlanRound {
        let clock = ContinuousClock()
        let start = clock.now
        let request = Self.request(bundle: bundle, transcript: transcript, model: client.model)
        let interaction: Interaction
        do {
            interaction = try await client.interact(request, timeout: timeout)
        } catch {
            return .failed(error.summary, latencyMs: Int((clock.now - start) / .milliseconds(1)))
        }
        let latency = Int((clock.now - start) / .milliseconds(1))
        guard interaction.usable else {
            return .failed("status \(interaction.status)", latencyMs: latency)
        }
        let calls = interaction.functionCalls
        if calls.isEmpty {
            return .silent(steps: interaction.rawSteps, usage: interaction.usage, latencyMs: latency)
        }
        return .calls(calls, steps: interaction.rawSteps, usage: interaction.usage, latencyMs: latency)
    }
}

/// What a plan is made from.
public struct PlanBundle: Sendable {
    public var query: String
    public var exchanges: [Exchange]
    public var facts: [String]
    public var memories: [MemoryRecord]
    public var tools: [ToolDeclaration]
    public var context: AnswerContext

    public init(query: String, exchanges: [Exchange], facts: [String], memories: [MemoryRecord], tools: [ToolDeclaration], context: AnswerContext) {
        self.query = query
        self.exchanges = exchanges
        self.facts = facts
        self.memories = memories
        self.tools = tools
        self.context = context
    }
}

public enum PlanRound: Sendable, Equatable {
    /// The calls asked for, in order, and every model step verbatim for the next round.
    case calls([FunctionCall], steps: [JSONValue], usage: AnswerUsage?, latencyMs: Int)
    /// The model wrote text and called nothing: nothing to do.
    case silent(steps: [JSONValue], usage: AnswerUsage?, latencyMs: Int)
    case failed(String, latencyMs: Int)
}
