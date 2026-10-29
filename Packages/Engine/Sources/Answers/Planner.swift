import Foundation
import Engine

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
    /// Accuracy over speed: the planner thinks. "minimal" was the first
    /// setting, when only multi-step queries were planned (2026-10-27).
    public static let thinkingLevel = "high"
    /// Room for the thoughts and a few calls with long queries; a call is
    /// under a hundred tokens, and nothing is paid for that is not produced.
    public static let maxOutputTokens = 1000

    /// The field every tool takes: what to run it on.
    public static let queryField = ArgumentSchema.Field(
        name: "query", kind: .text,
        description: "the request to run it on, complete and self-contained, with anything learned in earlier steps folded in: for narrative and one_line a question for the device to answer, never the answer itself"
    )

    /// The four tools the executor answers itself: a question on the
    /// sheet, something said straight to the user, a thing opened by its
    /// handle, and the end of the plan.
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
    /// Text the planner already holds in full, shown on a card as it is: no
    /// second model reads it. The description is the whole rule for when.
    public static let sayTool = ToolDeclaration(
        name: "say",
        description: "Show the user something you already know in full, as the complete answer, on a card: from the facts you were given, the memories shown to you, or earlier steps' results, including \"I don't know that yet\" when the facts hold nothing on a question about their life. In your own voice to them: you for them, I for yourself. Never for anything that needs knowledge beyond that, which narrative and one_line are for: a page or a thing you have only seen listed by its title is not something you know, so a comparison, a summary or a judgement of it goes through narrative with about, never say.",
        parameters: [
            "type": "object",
            "properties": ["text": ["type": "string", "description": "what to show, complete, a sentence or a few"]],
            "required": ["text"],
            "additionalProperties": false,
        ]
    )
    /// A thing from the listing, shown: the device opens the page, loads the
    /// search, or shows the saved answer. The model never carries the address.
    public static let openTool = ToolDeclaration(
        name: "open",
        description: "Show things from the listing or from a step's result, by handle. One thing: a page loads, a search loads its results, an answer or a note is shown as it is. Several of the same kind (notes, or memories) are shown together in a grid, which is how the user sees more than one at once; a tap opens one. Puts its result on screen.",
        parameters: [
            "type": "object",
            "properties": ["things": ["type": "array", "items": ["type": "string"], "description": "the handles of the things to show, such as [\"m2\"] or [\"n1\", \"n2\", \"n3\"]"]],
            "required": ["things"],
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

    /// Every instinct as a tool, in registry order, then `ask`, `say`, `open` and `done`.
    public static func tools(for registry: [InstinctSpec]) -> [ToolDeclaration] {
        registry.map { spec in
            let schema = ArgumentSchema(fields: [queryField] + spec.arguments.fields)
            return ToolDeclaration(name: spec.id, description: describe(spec), parameters: schema.jsonSchema())
        } + [askTool, sayTool, openTool, doneTool]
    }

    static func describe(_ spec: InstinctSpec) -> String {
        var text = spec.criterion.what
        if !spec.criterion.notFor.isEmpty { text += " Not for: " + spec.criterion.notFor }
        if spec.instinct == .recall {
            // In a plan the recall finds; the plan decides what to do with what it found.
            text += " In a plan it shows nothing: its result names what it found, by handle, for open, say, or an answer's about."
        } else if spec.instinct == .notebook {
            text += " Every note of my notebook is in the listing: the one the request means goes in note, by handle, whatever words it used for it (\"my watchlist\" means a note titled Watch List); a page or answer to keep goes in item, by handle, and its title and link go in. A topic with no note handle makes a new note by that name (add, new) or fails (open, delete). Every note is listed whole with its lines numbered: text is the exact lines to add, in the marks of the lines around where they go, and after is the number of the line they follow. \"add milk\" to a bulleted shopping list writes \"- milk\" after its last item; \"add eggs to the groceries\" in a note with a groceries list and a packing list writes \"- eggs\" after the last grocery line, not at the end; \"start a packing list here with passport\" in a note of prose writes a blank line, \"## Packing\" and \"- [ ] passport\" at the end; a page kept by handle goes as \"- {item}\" in a list and \"{item}\" alone in prose, and a note that is empty starts the way its purpose reads (a watch list or shopping list as a list, a thought as prose); \"add that the plumber comes tuesday\" to a note of prose, or as a new note, writes the sentence \"The plumber comes Tuesday.\", never a one-item list; a numbered list gets the next number. Shows the note afterwards."
        } else {
            text += spec.showsLayer ? " Puts its result on screen." : " Shows nothing; a mark says what was done."
        }
        switch spec.sideEffects {
        case .paid: text += " Costs money; the device confirms it with the user first."
        case .destructive: text += spec.asksItself ? " Asks the user itself before acting." : " Cannot be undone; the device confirms it with the user first."
        case .none, .reversible: break
        }
        return text
    }

    public static func system(facts: [String], context: AnswerContext, persona: Persona = Persona()) -> String {
        var lines = [
            persona.identityLine,
            "You plan what you do for a request \(persona.user) made. The device's classifier was not sure which single tool fits it, or saw several steps in it, which is why you are reading it: understand the request, then act. It may need one tool or several. Nothing you write outside a tool call is shown to anyone. You act only by calling the tools below, and the device runs them.",
            "",
            "Rules:",
            "- To tell \(persona.user) something you already know in full (from the facts below, the memories shown to you, or earlier steps' results), call say with it. To tell them something you would have to work out or look up, call narrative or one_line with a complete, self-contained question in its query, with whatever you learned from earlier steps folded in; the device answers it. Never write an answer into a question.",
            "- To confirm something, to choose, or to get a value the request leaves out, call ask; the answer comes back as the result.",
            "- A tool that costs money or cannot be undone is confirmed with \(persona.user) by the device before it runs, not by you.",
            "- \(InstinctSpec.all.filter { $0.showsLayer && $0.instinct != .recall }.map(\.id).joined(separator: ", ")), say and open each put a result on screen, and a later one replaces the earlier: end on what \(persona.user) should see.",
            "- The listing tags each earlier thing of this session (p1, p2), each memory (m1, m2), each note of my notebook (n1, n2) and each link in view on the screen (s1, s2). A tool that takes a thing takes its handle, and only a handle from the listing or from a step's result, never one you made up. recall's result names what it found by handle; open shows one; say, or an answer with about, tells \(persona.user) about one.",
            "- \(Screen.rule) \(Screen.pictureRule) A link in view is opened by its handle (open with s2), kept by its handle (notebook's item), and its address, which the listing gives, may be said when \(persona.user) asks for the link.",
            "- When an answer on the sheet is something lasting about \(persona.user) or their life, call remember with it next.",
            "- remember and forget show \(persona.user) a mark saying what was kept or dropped: never also say it.",
            "- A request about \(persona.users) own life is served from what you know of them below: remember what they tell you, recall what they ask for, answer from the facts, and say you don't know when they hold nothing. Never make anything up about \(persona.user).",
            "- Call several tools in one turn only when none needs another's result; otherwise one at a time, and read the result before the next.",
            "- A step whose result says it ran is done: never call it again with the same arguments.",
            "- Call done when the request has been handled, or when nothing you can do would help.",
            "- Date and time: \(AnswerPrompt.dateText(context)). Locale: \(context.locale.identifier).",
            "",
            "\(AnswerPrompt.factsHeading(persona)) (told earlier; let it shape what you do, never repeat it):",
        ]
        lines += facts.isEmpty ? ["- nothing yet"] : facts.map { "- " + $0 }
        return lines.joined(separator: "\n")
    }

    /// The request, the exchanges it depends on, and the memories the
    /// words point at, as the plan's first turn, each tagged with its handle.
    public static func input(query: String, exchanges: [Exchange], memories: [MemoryRecord], now: Date, calendar: Calendar = .current) -> String {
        input(query: query, things: ThingTable(exchanges: exchanges, memories: memories), now: now, calendar: calendar)
    }

    /// `lead` is the one line before the request that says why the planner
    /// has it: what an instinct tried and could not do (`failureLead`), or
    /// that the classifier picked an instinct that is reasoned (`pickedLead`).
    public static func input(query: String, things: ThingTable, now: Date, calendar: Calendar = .current, lead: String? = nil, screen: Screen? = nil) -> String {
        var lines = ["Request: \(query)"]
        if let lead, !lead.isEmpty {
            lines.append("")
            lines.append(lead)
        }
        let exchanges = things.exchangeEntries
        if !exchanges.isEmpty {
            lines.append("")
            lines.append("Earlier in this session (oldest first):")
            lines += exchanges.map { "- " + ThingTable.line($0, now: now, calendar: calendar) }
        }
        let memories = things.memoryEntries
        if !memories.isEmpty {
            lines.append("")
            lines.append("Seen in this app before, the newest (recall finds the rest):")
            lines += memories.map { "- " + ThingTable.line($0, now: now, calendar: calendar) }
        }
        let notes = things.noteEntries
        lines.append("")
        if notes.isEmpty {
            // Said outright, so a write makes a note instead of asking which.
            lines.append("In my notebook: no notes yet.")
        } else {
            lines.append("In my notebook, every note (newest first):")
            lines += notes.map { "- " + ThingTable.line($0, now: now, calendar: calendar) }
        }
        if let screen {
            // The screen as the user sees it, whole: the links by their handles.
            lines.append("")
            lines.append(screen.block(whole: true, handles: things.itemHandles))
        }
        return lines.joined(separator: "\n")
    }

    /// The plan's first turn: the words, and the screen's picture beside
    /// them when there is one.
    public static func firstTurn(_ text: String, picture: Data?) -> InteractionStep {
        guard let picture, !picture.isEmpty else { return .userText(text) }
        return .userParts([.text(text), .image(picture, mimeType: "image/jpeg")])
    }

    /// The lead line for an instinct that tried first and could not.
    public static func failureLead(_ reason: String) -> String {
        "Tried first, and could not: \(reason). Do what the request needs another way, or say so."
    }

    /// The lead line for an instinct the classifier picked with confidence
    /// but that is reasoned: the planner runs it with everything in view.
    public static func pickedLead(_ instinct: Instinct) -> String {
        "The classifier picked \(instinct.rawValue) with confidence; you run it, because it acts on things: fill its values from the request and the listing, and call it."
    }

    /// What a recall found, as a step's result: the handles minted for the
    /// records, each with what it is.
    public static func found(_ handles: [String], in things: ThingTable, now: Date, calendar: Calendar = .current) -> String {
        guard !handles.isEmpty else { return "found nothing" }
        let lines = handles.compactMap { handle in things.entries.first { $0.handle == handle }.map { ThingTable.line($0, now: now, calendar: calendar) } }
        return "found " + lines.joined(separator: "; ")
    }

    public static func request(bundle: PlanBundle, transcript: [InteractionStep], model: String = model) -> InteractionRequest {
        InteractionRequest(
            model: model,
            systemInstruction: system(facts: bundle.facts, context: bundle.context, persona: bundle.persona),
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
    public var persona: Persona
    /// What is on screen as the request is made, when it could be read.
    public var screen: Screen?

    public init(query: String, exchanges: [Exchange], facts: [String], memories: [MemoryRecord], tools: [ToolDeclaration], context: AnswerContext, persona: Persona = Persona(), screen: Screen? = nil) {
        self.query = query
        self.exchanges = exchanges
        self.facts = facts
        self.memories = memories
        self.tools = tools
        self.context = context
        self.persona = persona
        self.screen = screen
    }
}

public enum PlanRound: Sendable, Equatable {
    /// The calls asked for, in order, and every model step verbatim for the next round.
    case calls([FunctionCall], steps: [JSONValue], usage: AnswerUsage?, latencyMs: Int)
    /// The model wrote text and called nothing: nothing to do.
    case silent(steps: [JSONValue], usage: AnswerUsage?, latencyMs: Int)
    case failed(String, latencyMs: Int)
}
