import Foundation
import Engine

/// Advanced reasoning's one call shape: the request, its earlier
/// exchanges, the facts and the open webpages go to Gemini
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
    /// Room for the thoughts and the calls: the budget counts the thinking,
    /// and at 1,000 a rewrite of a note, a comparison or a long list of links
    /// spent it all thinking and came back incomplete with no call at all
    /// (four such rounds in the eval cache, each about 950 thought tokens
    /// and no output; 2026-10-31). Nothing is paid for that is not produced,
    /// so a plain round costs what it did.
    public static let maxOutputTokens = 8000

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

    /// On the page-opening tools, with `screen`: a site already open comes
    /// forward instead of opening again, unless the user asked for a new one.
    public static let freshField = ArgumentSchema.Field(
        name: "fresh", kind: .boolean,
        description: "true only when the user asked for a new one of a site already open (\"open a new youtube\", \"another tab for amazon\"); otherwise a page already open among the webpages is brought forward as it stands, and this is false or left out",
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
                "question": ["type": "string", "description": "the question, in a line, in your own voice"],
                "options": ["type": "array", "items": ["type": "string"], "description": "one to three choices, the expected one first, each the thing's name as the user knows it (a note's title, a place), never a handle; leave out for a typed line"],
            ],
            "required": ["question"],
            "additionalProperties": false,
        ]
    )
    /// Text the planner already holds in full, shown in the bubble as it is: no
    /// second model reads it. The description is the whole rule for when.
    public static let sayTool = ToolDeclaration(
        name: "say",
        description: "Show the user something you already know in full, as the complete answer, in a short reply over what they are looking at (a line or a card, never the whole screen): from the facts you were given, the open webpages listed, or earlier steps' results (what I read on my screen included), including \"I don't know that yet\" when the facts hold nothing on a question about their life. Never to retell something the listing holds as a thing: a note's lines, a page's content, an earlier answer's text. Those are shown as themselves with open (a note's lines as a card, a page, an answer), and the user reads on into them; say is for a fact with no thing to show (a count, a yes or no read off a note, a line of your own), or to tell the user what you could not do and what would, while you keep checking, and a question about a thing that must be worked out goes through narrative with about. In your own voice, as How you speak describes: you for them, I for yourself. Never for anything that needs knowledge beyond that, which narrative and one_line are for: a page or a thing you have only seen listed by its title is not something you know, so a comparison, a summary or a judgement of it goes through narrative with about, never say.",
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
        description: "Show things from the listing or from a step's result, by handle. One thing: a page loads, a search loads its results, an answer or a note is shown as it is. Several of the same kind (notes, or open webpages) are shown together in a grid, which is how the user sees more than one at once; a tap opens one. An open webpage (w2) is brought forward as it stands, loaded or reloaded to where it was, never opened again. Puts its result on the user's screen. A page a step opened on my screen (p3 in its result, or listed as read on my screen) is brought forward to the user's screen as it is, already loaded: how the user gets to see what I found. A request for a thing the listing holds (\"what's on my watchlist\", \"show me that Lisbon article\", \"what did you say about the retainer\") is open with its handle, never a retelling of it in say: the user gets the thing as it is, and reads on into it. A question about the thing (\"was that article any good\", \"is it worth reading\", \"which of these is cheapest\") is not a request for it: that is an answer with the thing in about (after a look, when the page holds more than the block shows), not open.",
        parameters: [
            "type": "object",
            "properties": ["things": ["type": "array", "items": ["type": "string"], "description": "the handles of the things to show, such as [\"w2\"] or [\"n1\", \"n2\", \"n3\"]"]],
            "required": ["things"],
            "additionalProperties": false,
        ]
    )
    /// Reads more of a page that is open than the screen block holds. The
    /// device runs the probe and sends the result back as text; links it
    /// finds become `s` handles like the ones in view.
    public static let lookTool = ToolDeclaration(
        name: "look",
        description: "Read a thing in full, by its handle, when the request asks for what the listing or the screen block does not hold. A page: the text further down (text, numbered by paragraph; from continues it), every link on it (links, in screen order, each with a handle to open or keep), its headings with their paragraph numbers (outline), its tables (tables). A note: its lines numbered (text), its links as handles (links), its headings (outline). An answer: its text (text, numbered by paragraph). An open webpage: as a page, when it is loaded; else open it first. The block already holds what is in view, the rest of a page's text up to its cap and its own data, and the listing holds every note up to its cap: when the answer is there, do not look; when it is not, look before you guess, never after. For how a page looks (a colour, a position, a layout), read the picture instead. With thing left out, reads the newest page on my screen from this plan, else whatever is on the user's screen, page, note or answer; thing names another by handle: a page on my screen from a step's result (p3), anything in the listing (p1, n2, w1); a link (s2) is not an open thing: open it first.",
        parameters: [
            "type": "object",
            "properties": [
                "thing": ["type": "string", "description": "the handle of the thing to read, when it is not the one I would read by default: p3 from a step's result, p1, n2 or w1 from the listing; omit for the newest page on my screen from this plan, else whatever is on the user's screen"],
                "what": ["type": "string", "enum": ["text", "links", "outline", "tables"], "description": "what to read"],
                "from": ["type": "integer", "description": "the paragraph or link number to continue from, as the last result numbered them; omit to start at the top"],
            ],
            "required": ["what"],
            "additionalProperties": false,
        ]
    )

    /// Open webpages closed by handle, or every one: the one way a webpage
    /// goes besides a new query from the middle of the row.
    public static let closeTool = ToolDeclaration(
        name: "close",
        description: "Close open webpages, by handle (w2) or every one (all), when the user asks to close, get rid of, or clear them (\"close this\", \"close the dyson page\", \"close everything\", \"close all the youtube ones\"). Nothing else closes a webpage: an answer, a note or a question is not one. The user sees the webpage go; the one they were on moves to its neighbour.",
        parameters: [
            "type": "object",
            "properties": ["things": ["type": "array", "items": ["type": "string"], "description": "the handles to close, such as [\"w2\"] or [\"w1\", \"w4\"], or [\"all\"] for every open webpage"]],
            "required": ["things"],
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

    /// Every instinct as a tool, in registry order, then `ask`, `say`, `open`, `look`, `close` and `done`.
    public static func tools(for registry: [InstinctSpec]) -> [ToolDeclaration] {
        registry.map { spec in
            let schema = ArgumentSchema(fields: fields(for: spec))
            return ToolDeclaration(name: spec.id, description: describe(spec), parameters: schema.jsonSchema())
        } + [askTool, sayTool, openTool, lookTool, closeTool, doneTool]
    }

    /// A tool's fields: the query, the screen and fresh for a page-opening
    /// tool, then the instinct's own. The executor validates a call against the same.
    public static func fields(for spec: InstinctSpec) -> [ArgumentSchema.Field] {
        [queryField] + (opensPage(spec) ? [screenField, freshField] : []) + spec.arguments.fields + (spec.instinct == .notebook ? [removeField] : [])
    }

    static func describe(_ spec: InstinctSpec) -> String {
        var text = spec.criterion.what
        if !spec.criterion.notFor.isEmpty { text += " Not for: " + spec.criterion.notFor }
        if spec.instinct == .recall {
            // In a plan the recall finds; the plan decides what to do with what it found.
            text += " In a plan it shows nothing: its result names what it found, by handle, for open, say, or an answer's about."
        } else if spec.instinct == .notebook {
            text += " Every note of my notebook is in the listing: the one the request means goes in note, by handle, whatever words it used for it (\"my watchlist\" means a note titled Watch List); a page or answer to keep goes in item, by handle, or several handles separated by commas (\"s5, s6, s7\" after a look at the links), each becoming a line of its own where {item} stands. A topic with no note handle makes a new note by that name (add, new) or fails (open, delete). text is the lines to write: when the request dictates them, they are the request's own words, never a retelling of the thing on screen. Every note is listed whole with its lines numbered, and a line whose words stand in square brackets is a link (the address is the device's, never written): \"the ones with links\" and \"the ones without\" are read off the brackets, and a rewrite copies a bracketed title as it stands, which the device writes back as the link; text is the exact lines to add, in the marks of the lines around where they go, and after is the number of the line they follow. \"add milk\" to a bulleted shopping list writes \"- milk\" after its last item; \"add eggs to the groceries\" in a note with a groceries list and a packing list writes \"- eggs\" after the last grocery line, not at the end; \"start a packing list here with passport\" in a note of prose writes a blank line, \"## Packing\" and \"- [ ] passport\" at the end; a page kept by handle goes as \"- {item}\" in a list and \"{item}\" alone in prose; a link always goes into a note as the thing's handle in braces inside text, on its own line (\"- {s3}\", \"{p1}\"), with the handle in item as well, which the device writes as a clickable link carrying the page's title, never as an address written out, which would stand in the note as plain text; and a note that is empty starts the way its purpose reads (a watch list or shopping list as a list, a thought as prose); \"add that the plumber comes tuesday\" to a note of prose, or as a new note, writes the sentence \"The plumber comes Tuesday.\", never a one-item list; a numbered list gets the next number. The note to write in is the one the request names, else the one note in view; in view means on the screen or in the bubble (the listing's last blocks name them), and a note merely listed in my notebook is not in view. Only when two notes are in view and the request names neither (\"change the bullet points to checkboxes\" with one note on screen and another in the bubble) ask which first, by their titles, and never write to both; with one note in view, write to it without asking, whatever else the notebook holds. A page or video kept into a note still goes in item by handle, whichever note takes it. Taking lines out is remove, by their numbers, never a rewrite of the rest, and a note emptied is a note with no lines, never a deleted one (delete only when the request says delete): the listing shows a kept page as its title, and a rewrite that copies the title loses nothing only because the device writes the link back, so replace is for new wording of the whole note. A write shows a line naming the note and what went in; open shows the note itself as a card the user reads on into: a request to see a note (\"what's on my watchlist\") is open, never a retelling of its lines in say."
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
            persona.speakerLine,
            "You plan what you do for a request \(persona.user) made. The device's classifier was not sure which single tool fits it, or saw several steps in it, which is why you are reading it: understand the request, then act. It may need one tool or several. Nothing you write outside a tool call is shown to anyone. You act only by calling the tools below, and the device runs them.",
            "",
            Voice.guide(persona),
            "This is how say, ask and every line of yours that \(persona.user) reads sound. A fact you keep with remember is not said to anyone: it is written about \(persona.user) by name, in the third person, as the facts below are.",
            "",
            "Rules:",
            "- To tell \(persona.user) something you already know in full (from the facts below, the open webpages listed, or earlier steps' results), call say with it. To tell them something you would have to work out or look up, call narrative or one_line with a complete, self-contained question in its query, with whatever you learned from earlier steps folded in; the device answers it. Never write an answer into a question.",
            "- To confirm something, to choose, or to get a value the request leaves out, call ask; the answer comes back as the result, with the question beside it. ask does nothing itself: after a yes-like answer (\"Delete\", \"Yes\", \"Go ahead\") call the step that does it; after a no-like one (\"Keep\", \"No\", \"Leave it\") say in a line that nothing was changed, or end; never report something done that no step did.",
            "- A tool that costs money or cannot be undone is confirmed with \(persona.user) by the device before it runs, not by you.",
            "- There are two screens. \(persona.user) has theirs, where everything they see goes: \(InstinctSpec.all.filter { $0.showsLayer && $0.instinct != .recall && !pageTools.contains($0.instinct) }.map(\.id).joined(separator: ", ")), say and open put their result there, each staying under the one before until the next request: so never say what a step has already shown (a note card says what was written, an answer answers), and after a step that showed something call done unless something is still missing (a caveat, a question). I have a screen of my own, where I read: \(InstinctSpec.all.filter { opensPage($0) }.map(\.id).joined(separator: ", ")) open their page there unless screen is user, and nothing on my screen is seen by \(persona.user). A page on my screen comes back in the step's result with a handle (p3): look reads it (thing: p3), open brings it forward to \(persona.users) screen as it is, notebook's item keeps it, and an answer's about names it. A question is read on my screen and answered in a line or a card; a page or results \(persona.user) asked to see open on theirs.",
            "- The listing tags each earlier thing of this session (p1, p2), each open webpage (w1, w2; what a browser calls tabs, open until \(persona.user) closes them), each note of my notebook (n1, n2) and each link in view on the screen (s1, s2). A tool that takes a thing takes its handle, and only a handle from the listing or from a step's result, never one you made up. The last block names what is on the screen by its handle (\"On screen, n1: my note …\"): \"this\", \"these notes\", \"this page\", \"the one I'm looking at\" is that handle, whatever kind of thing it is, and a step takes it as any other handle. When the request itself carries the thing to write or keep (a sentence of instructions, a fact, a list, a rule), \"it\", \"this\" and \"that\" are that content, whatever is on screen: \"make answers stricter about what they bold and add subtitles, and add it to my notes about my project\" writes those instructions, never the answer on screen. Only when the request carries nothing of its own and more than one thing in view fits does \"it\" need asking about. The request stands under Request:, cleaned of dictation noise; \"As spoken\" is the exact wording when it differs, and it wins on any doubt about what was meant. A correction (\"no, not that\", \"I meant the rules I talked about\", \"not the Stardew text\") points at the request before, listed with its words (\"You asked …\") and with what was written; act on those words, and never ask \(persona.user) to say again what the listing already holds. Two places are in view at once when the bubble holds a reply over the screen, and the listing names both (\"On screen, n1: …\" and \"In the bubble, n3: …\"). In view means named in those two blocks, nothing else: the notebook's other notes and the session's earlier things are not in view. When the request points at a thing without naming it (\"this\", \"these\", \"the bullet points\") and more than one thing in view fits, ask which before any step that writes, with the things' titles as the options (\"Which note? Watchlist, or AI project?\"); when one thing is in view, it is that thing, and asking would be a nuisance. Ask which, never whether: a step that needs confirming (a delete, a payment) is confirmed by the device when it runs, so asking first would ask twice. What a handle does not show in the listing is one look away (look with that handle): a note's lines past the cap, an answer's text, a loaded webpage's text, a page's text further down. Never guess what a thing holds. recall's result names what it found by handle. When the request asks for a thing in the listing, open shows it as itself; say tells a fact that has no thing to show (a count, whether a line is in a note); an answer with about works something out about one. Never retell a thing you could show. A follow-up to the answer \(persona.user) is reading (\"could that be why?\", \"why?\", \"and in km?\") is narrative or one_line with that answer in about and the follow-up itself as the query, not reworded: the device grows the conversation with the reply as its next turn.",
            "- \(Screen.rule) \(Screen.pictureRule) A link in view is opened by its handle (open with s2), kept by its handle (notebook's item), and its address, which the listing gives, may be said when \(persona.user) asks for the link; in a note it is never written out: the handle in braces is the link.",
            "- look reads more of an open page than the screen block holds; what it finds comes back as its result, and the links it lists carry handles (s5, s6) used like any other: opened, kept, or said. Look once for what is asked, continue with from only when the result says it was cut, and never look for what the block already shows.",
            "- Every lasting fact the request itself states is read and kept by the device as the words arrive, with a mark: never call remember for what the request says. Call remember for something lasting about \(persona.users) own life that came out of an answer or of ask, never for a decision or detail inside something they are making (a project's mascot, a logo's colour): the work keeps that.",
            "- remember and forget show \(persona.user) a mark saying what was kept or dropped: never also say it.",
            "- A request about \(persona.users) own life is served from what you know of them below: remember what they tell you, recall what they ask for, answer from the facts, and say you don't know when they hold nothing. Never make anything up about \(persona.user).",
            "- Call several tools in one turn only when none needs another's result; otherwise one at a time, and read the result before the next.",
            "- A step whose result says it ran is done: never call it again with the same arguments.",
            "- Before the first step, judge what the request needs. An effect in the world no tool of yours produces (a booking, a call, a payment, a message sent) is not something to try: say in one line what you cannot do and what would do it (\"I'm afraid I can't book tables yet, sir. Their website or a quick call will.\"), then done. Information is always worth trying: a search often holds it outright.",
            "- While you work, judge progress, not attempts. A step that gained ground (an address where there was none, a page where there was a name) earns the next step, however many it takes. A step that gained nothing (the same results again, nothing usable) is the moment to tell \(persona.user), in one short line in your own voice, what you could not find and what would find it (\"I'm afraid I can't measure distances yet; Maps will tell you which is closer. I'll keep looking in the meantime.\"): say it first, in the very next call, since \(persona.user) is waiting and has no idea why, and only then keep checking with a different kind of step or a new angle, in case one more holds it; you have the time. Never say round counts, handles or tool names to \(persona.user).",
            "- Call done when the request has been handled, or, after saying what you could not do, when you have checked what was worth checking.",
            "- Date and time: \(AnswerPrompt.dateText(context)). Locale: \(context.locale.identifier).",
            "",
            "\(AnswerPrompt.factsHeading(persona)) (told earlier; let it shape what you do, never repeat it):",
        ]
        lines += facts.isEmpty ? ["- nothing yet"] : facts.map { "- " + $0 }
        return lines.joined(separator: "\n")
    }

    /// How many of the newest earlier things carry the user's words in the listing.
    public static let askedListed = 5

    /// The request, the exchanges it depends on, and the open webpages, as
    /// the plan's first turn, each tagged with its handle.
    public static func input(query: String, exchanges: [Exchange], webpages: [Webpage], now: Date, calendar: Calendar = .current) -> String {
        input(query: query, things: ThingTable(exchanges: exchanges, webpages: webpages), now: now, calendar: calendar)
    }

    /// `lead` is the one line before the request that says why the planner
    /// has it: what an instinct tried and could not do (`failureLead`), or
    /// that the classifier picked an instinct that is reasoned (`pickedLead`).
    public static func input(query: String, things: ThingTable, now: Date, calendar: Calendar = .current, lead: String? = nil, screen: Screen? = nil, screenNoteID: UUID? = nil, bubble: Screen? = nil, bubbleNoteID: UUID? = nil, spoken: String? = nil) -> String {
        var lines = ["Request: \(query)"]
        // The words as the user said them, when the reading changed them: the
        // planner resolves "it" and "this" from these, never from a rewrite.
        if let spoken, Substance.differs(spoken, query) { lines.append("As spoken: \"\(spoken)\"") }
        if let lead, !lead.isEmpty {
            lines.append("")
            lines.append(lead)
        }
        let exchanges = things.exchangeEntries
        if !exchanges.isEmpty {
            lines.append("")
            lines.append("Earlier in this session (oldest first):")
            let noteHandles = things.noteHandles
            let webpageHandles = things.webpageHandles
            // The newest few carry the user's words, so "the rules I talked about" has them in view.
            let worded = max(exchanges.count - askedListed, 0)
            lines += exchanges.enumerated().map { "- " + ThingTable.line($0.element, now: now, calendar: calendar, noteHandles: noteHandles, webpageHandles: webpageHandles, withWords: $0.offset >= worded) }
        }
        let webpages = things.webpageEntries
        if !webpages.isEmpty {
            lines.append("")
            lines.append("Open webpages, newest first (what the user has open, kept until closed; open brings one forward, close closes; recall finds one by what it is about):")
            lines += webpages.map { "- " + ThingTable.line($0, now: now, calendar: calendar) }
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
        let screenHandle = screen.flatMap { things.screenHandle(for: $0, noteID: screenNoteID) }
        if let screen {
            // The screen as the user sees it, whole: the thing on it by the
            // handle it already has, the links by theirs.
            lines.append("")
            lines.append(screen.block(whole: true, handles: things.itemHandles, handle: screenHandle))
        }
        // The bubble is a second place in view: the reply over the screen,
        // named by its handle too, so two things in view read as two.
        if let bubble, let handle = things.screenHandle(for: bubble, noteID: bubbleNoteID), handle != screenHandle {
            lines.append("")
            lines.append(bubble.block(whole: true, handle: handle, place: "In the bubble"))
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
    /// The result of a look: the links found, by handle, under `lead` (a
    /// page's by default), then the text read.
    public static func looked(what: String, text: String, handles: [String], in things: ThingTable, lead: String? = nil) -> String {
        let lines = handles.compactMap { handle in things.entries.first { $0.handle == handle }.map { ThingTable.line($0, now: .now) } }
        if text.isEmpty, lines.isEmpty {
            if let lead { return lead + " nothing of that kind (\(what))" }
            return "nothing of that kind on the page (\(what)): it may be drawn rather than written; the picture shows how it looks"
        }
        var out: [String] = []
        if !lines.isEmpty {
            out.append(lead ?? "Links on the page, in order:")
            out += lines.map { "- " + $0 }
        } else if let lead {
            out.append(lead)
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
            // "incomplete" with no call: the output budget ran out, usually
            // while thinking; the executor asks the round once more.
            return .silent(steps: interaction.rawSteps, usage: interaction.usage, latencyMs: latency, incomplete: interaction.status == "incomplete")
        }
        return .calls(calls, steps: interaction.rawSteps, usage: interaction.usage, latencyMs: latency)
    }
}

/// What a plan is made from.
public struct PlanBundle: Sendable {
    public var query: String
    public var exchanges: [Exchange]
    public var facts: [String]
    public var tools: [ToolDeclaration]
    public var context: AnswerContext
    public var persona: Persona
    /// What is on screen as the request is made, when it could be read.
    public var screen: Screen?

    public init(query: String, exchanges: [Exchange], facts: [String], tools: [ToolDeclaration], context: AnswerContext, persona: Persona = Persona(), screen: Screen? = nil) {
        self.query = query
        self.exchanges = exchanges
        self.facts = facts
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
    case silent(steps: [JSONValue], usage: AnswerUsage?, latencyMs: Int, incomplete: Bool = false)
    case failed(String, latencyMs: Int)
}
