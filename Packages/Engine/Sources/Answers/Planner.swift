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

    /// The field every page-opening tool takes: whose screen the page goes
    /// to. Jarbits's own by default, where only it reads; the user's when
    /// they asked to see the page. The planner's decision alone: the device
    /// puts the page where it was told. Declared here, beside the query
    /// field, never on the instinct's spec: a field on the spec would become
    /// routing questions and change what Jev is sent.
    /// The notebook tool's field for taking lines out, on the tool alone for
    /// the same reason: the notebook's `action` is one of Jev's questions,
    /// and its options stay as they are.
    public static let removeField = ArgumentSchema.Field(
        name: "remove", kind: .text,
        description: "the numbers of the lines to take out of the note, as the listing numbers them, separated by commas, a run as 2-5 (\"take eggs off my shopping list\": the eggs line; \"remove everything except the framework and midterms videos\": every other line); every line not named stays exactly as it is, its link included; with it, text is null unless lines are also added",
        required: false
    )

    public static let screenField = ArgumentSchema.Field(
        name: "screen", kind: .choice(["mine", "user"]),
        description: "which screen the page opens on. mine: my own screen, where only I read it, to find something out before I answer; the user never sees it, and the result gives it a handle for look and open (\"when does lehigh pizza open\", \"what's the price of the kilburn two\", \"is this video's advice sound\": results on my screen, a look, then one_line or narrative). user: the user's screen, where it shows at once, when they asked to see the page or the results themselves (\"pull up youtube\", \"look up flights to lima\", \"show me pictures of capybaras\"). Every page step says which.",
        required: true
    )
    /// The instincts that open a page, and so take the screen field.
    public static let pageTools: Set<Instinct> = [.webResults, .image, .video, .map, .stock, .site]
    public static func opensPage(_ spec: InstinctSpec) -> Bool { spec.showsLayer && pageTools.contains(spec.instinct) }

    /// The four tools the executor answers itself: a question on the
    /// sheet, something said straight to the user, a thing opened by its
    /// handle, and the end of the plan.
    public static let askTool = ToolDeclaration(
        name: "ask",
        description: "Put one short question to the user, in a short reply over what they are looking at, and get the answer back: to confirm, to choose, or to get a value the request leaves out. Give one to three options with the expected one first, or none for a line of text. The answer comes back as the result with the question beside it; asking changes nothing on its own.",
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
    /// Text the planner already holds in full, shown in the bubble as it is: no
    /// second model reads it. The description is the whole rule for when.
    public static let sayTool = ToolDeclaration(
        name: "say",
        description: "Show the user something you already know in full, as the complete answer, in a short reply over what they are looking at (a line or a card, never the whole screen): from the facts you were given, the memories shown to you, or earlier steps' results (what I read on my screen included), including \"I don't know that yet\" when the facts hold nothing on a question about their life. Never to retell something the listing holds as a thing: a note's lines, a page's content, an earlier answer's text. Those are shown as themselves with open (a note's lines as a card, a page, an answer), and the user reads on into them; say is for a fact with no thing to show (a memory, a count, a yes or no read off a note, a line of your own), and a question about a thing that must be worked out goes through narrative with about. In your own voice to them: you for them, I for yourself. Never for anything that needs knowledge beyond that, which narrative and one_line are for: a page or a thing you have only seen listed by its title is not something you know, so a comparison, a summary or a judgement of it goes through narrative with about, never say.",
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
        description: "Show things from the listing or from a step's result, by handle. One thing: a page loads, a search loads its results, an answer or a note is shown as it is. Several of the same kind (notes, or memories) are shown together in a grid, which is how the user sees more than one at once; a tap opens one. Puts its result on the user's screen. A page a step opened on my screen (p3 in its result, or listed as read on my screen) is brought forward to the user's screen as it is, already loaded: how the user gets to see what I found. A request for a thing the listing holds (\"what's on my watchlist\", \"show me that Lisbon article\", \"what did you say about the retainer\") is open with its handle, never a retelling of it in say: the user gets the thing as it is, and reads on into it. A question about the thing (\"was that article any good\", \"is it worth reading\", \"which of these is cheapest\") is not a request for it: that is an answer with the thing in about (after a look, when the page holds more than the block shows), not open.",
        parameters: [
            "type": "object",
            "properties": ["things": ["type": "array", "items": ["type": "string"], "description": "the handles of the things to show, such as [\"m2\"] or [\"n1\", \"n2\", \"n3\"]"]],
            "required": ["things"],
            "additionalProperties": false,
        ]
    )
    /// Reads more of a page that is open than the screen block holds. The
    /// device runs the probe and sends the result back as text; links it
    /// finds become `s` handles like the ones in view.
    public static let lookTool = ToolDeclaration(
        name: "look",
        description: "Read more of a page that is open, when the request asks for what the screen block does not hold: the text further down (text, numbered by paragraph; from continues it), every link on the page (links, in screen order, each with a handle to open or keep), the headings with their paragraph numbers (outline), or the tables (tables). The block already holds what is in view, the rest of the text up to its cap, and the page's own data: when the answer is there, do not look. For how the page looks (a colour, a position, a layout), read the picture instead. Reads the page on my screen when a step of this plan opened one (the newest), else the page on the user's screen; page names another by handle: a page on my screen from a step's result (p3) or one on the user's screen from the listing (p1); a link (s2) is not an open page: open it first.",
        parameters: [
            "type": "object",
            "properties": [
                "page": ["type": "string", "description": "the handle of the page to read, when it is not the one I would read by default: p3 from a step's result, p1 from the listing; omit for the newest page on my screen, else the user's"],
                "what": ["type": "string", "enum": ["text", "links", "outline", "tables"], "description": "what to read"],
                "from": ["type": "integer", "description": "the paragraph or link number to continue from, as the last result numbered them; omit to start at the top"],
            ],
            "required": ["what"],
            "additionalProperties": false,
        ]
    )

    public static let doneTool = ToolDeclaration(
        name: "done",
        description: "Call once the request has been handled, or once nothing you can do would help. A step that showed something has handled it; a line saying so adds nothing.",
        parameters: ["type": "object", "properties": [:], "required": [], "additionalProperties": false]
    )

    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
    }

    /// Every instinct as a tool, in registry order, then `ask`, `say`, `open` and `done`.
    public static func tools(for registry: [InstinctSpec]) -> [ToolDeclaration] {
        registry.map { spec in
            let schema = ArgumentSchema(fields: fields(for: spec))
            return ToolDeclaration(name: spec.id, description: describe(spec), parameters: schema.jsonSchema())
        } + [askTool, sayTool, openTool, lookTool, doneTool]
    }

    /// A tool's fields: the query, the screen for a page-opening tool, then
    /// the instinct's own. The executor validates a call against the same.
    public static func fields(for spec: InstinctSpec) -> [ArgumentSchema.Field] {
        [queryField] + (opensPage(spec) ? [screenField] : []) + spec.arguments.fields + (spec.instinct == .notebook ? [removeField] : [])
    }

    static func describe(_ spec: InstinctSpec) -> String {
        var text = spec.criterion.what
        if !spec.criterion.notFor.isEmpty { text += " Not for: " + spec.criterion.notFor }
        if spec.instinct == .recall {
            // In a plan the recall finds; the plan decides what to do with what it found.
            text += " In a plan it shows nothing: its result names what it found, by handle, for open, say, or an answer's about."
        } else if spec.instinct == .notebook {
            text += " Every note of my notebook is in the listing: the one the request means goes in note, by handle, whatever words it used for it (\"my watchlist\" means a note titled Watch List); a page or answer to keep goes in item, by handle, or several handles separated by commas (\"s5, s6, s7\" after a look at the links), each becoming a line of its own where {item} stands. A topic with no note handle makes a new note by that name (add, new) or fails (open, delete). Every note is listed whole with its lines numbered: text is the exact lines to add, in the marks of the lines around where they go, and after is the number of the line they follow. \"add milk\" to a bulleted shopping list writes \"- milk\" after its last item; \"add eggs to the groceries\" in a note with a groceries list and a packing list writes \"- eggs\" after the last grocery line, not at the end; \"start a packing list here with passport\" in a note of prose writes a blank line, \"## Packing\" and \"- [ ] passport\" at the end; a page kept by handle goes as \"- {item}\" in a list and \"{item}\" alone in prose; a link always goes into a note as the thing's handle in braces inside text, on its own line (\"- {s3}\", \"{p1}\"), with the handle in item as well, which the device writes as a clickable link carrying the page's title, never as an address written out, which would stand in the note as plain text; and a note that is empty starts the way its purpose reads (a watch list or shopping list as a list, a thought as prose); \"add that the plumber comes tuesday\" to a note of prose, or as a new note, writes the sentence \"The plumber comes Tuesday.\", never a one-item list; a numbered list gets the next number. Taking lines out is remove, by their numbers, never a rewrite of the rest: the listing shows a kept page as its title, and a rewrite that copies the title loses nothing only because the device writes the link back, so replace is for new wording of the whole note. A write shows a line naming the note and what went in; open shows the note itself as a card the user reads on into: a request to see a note (\"what's on my watchlist\") is open, never a retelling of its lines in say."
        } else if opensPage(spec) {
            text += " Opens its page on my screen, where only I read it; on the user's screen when screen is user."
        } else {
            text += spec.showsLayer ? " Puts its result on the user's screen." : " Shows nothing; a mark says what was done."
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
            "- To confirm something, to choose, or to get a value the request leaves out, call ask; the answer comes back as the result, with the question beside it. ask does nothing itself: after a yes-like answer (\"Delete\", \"Yes\", \"Go ahead\") call the step that does it; after a no-like one (\"Keep\", \"No\", \"Leave it\") say in a line that nothing was changed, or end; never report something done that no step did.",
            "- A tool that costs money or cannot be undone is confirmed with \(persona.user) by the device before it runs, not by you.",
            "- There are two screens. \(persona.user) has theirs, where everything they see goes: \(InstinctSpec.all.filter { $0.showsLayer && $0.instinct != .recall && !pageTools.contains($0.instinct) }.map(\.id).joined(separator: ", ")), say and open put their result there, each staying under the one before until the next request: so never say what a step has already shown (a note card says what was written, an answer answers), and after a step that showed something call done unless something is still missing (a caveat, a question). I have a screen of my own, where I read: \(InstinctSpec.all.filter { opensPage($0) }.map(\.id).joined(separator: ", ")) open their page there unless screen is user, and nothing on my screen is seen by \(persona.user). A page on my screen comes back in the step's result with a handle (p3): look reads it (page: p3), open brings it forward to \(persona.users) screen as it is, notebook's item keeps it, and an answer's about names it. A question is read on my screen and answered in a line or a card; a page or results \(persona.user) asked to see open on theirs.",
            "- The listing tags each earlier thing of this session (p1, p2), each memory (m1, m2), each note of my notebook (n1, n2) and each link in view on the screen (s1, s2). A tool that takes a thing takes its handle, and only a handle from the listing or from a step's result, never one you made up. The last block names what is on the screen by its handle (\"On screen, n1: my note …\"): \"this\", \"these notes\", \"this page\", \"the one I'm looking at\" is that handle, whatever kind of thing it is, and a step takes it as any other handle. recall's result names what it found by handle. When the request asks for a thing in the listing, open shows it as itself; say tells a fact that has no thing to show (a memory, a count, whether a line is in a note); an answer with about works something out about one. Never retell a thing you could show. A follow-up to the answer \(persona.user) is reading (\"could that be why?\", \"why?\", \"and in km?\") is narrative or one_line with that answer in about and the follow-up itself as the query, not reworded: the device grows the conversation with the reply as its next turn.",
            "- \(Screen.rule) \(Screen.pictureRule) A link in view is opened by its handle (open with s2), kept by its handle (notebook's item), and its address, which the listing gives, may be said when \(persona.user) asks for the link; in a note it is never written out: the handle in braces is the link.",
            "- look reads more of an open page than the screen block holds; what it finds comes back as its result, and the links it lists carry handles (s5, s6) used like any other: opened, kept, or said. Look once for what is asked, continue with from only when the result says it was cut, and never look for what the block already shows.",
            "- Every lasting fact the request itself states is read and kept by the device as the words arrive, with a mark: never call remember for what the request says. Call remember for something lasting about \(persona.users) own life that came out of an answer or of ask, never for a decision or detail inside something they are making (a project's mascot, a logo's colour): the work keeps that.",
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
    public static func input(query: String, things: ThingTable, now: Date, calendar: Calendar = .current, lead: String? = nil, screen: Screen? = nil, screenNoteID: UUID? = nil) -> String {
        var lines = ["Request: \(query)"]
        if let lead, !lead.isEmpty {
            lines.append("")
            lines.append(lead)
        }
        let exchanges = things.exchangeEntries
        if !exchanges.isEmpty {
            lines.append("")
            lines.append("Earlier in this session (oldest first):")
            let noteHandles = things.noteHandles
            lines += exchanges.map { "- " + ThingTable.line($0, now: now, calendar: calendar, noteHandles: noteHandles) }
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
            // The screen as the user sees it, whole: the thing on it by the
            // handle it already has, the links by theirs.
            lines.append("")
            lines.append(screen.block(whole: true, handles: things.itemHandles, handle: things.screenHandle(for: screen, noteID: screenNoteID)))
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
    /// A look's result as the planner reads it: what the probe read, then
    /// the links it found, each by its new handle, as the screen block lists
    /// them. An empty read says so, so the planner falls back.
    public static func looked(what: String, text: String, handles: [String], in things: ThingTable) -> String {
        let lines = handles.compactMap { handle in things.entries.first { $0.handle == handle }.map { ThingTable.line($0, now: .now) } }
        if text.isEmpty, lines.isEmpty { return "nothing of that kind on the page (\(what)): it may be drawn rather than written; the picture shows how it looks" }
        var out: [String] = []
        if !lines.isEmpty {
            out.append("Links on the page, in order:")
            out += lines.map { "- " + $0 }
        }
        if !text.isEmpty { out.append(text) }
        return out.joined(separator: "\n")
    }

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
