import Foundation
import Testing
@testable import Answers
@testable import Engine

/// Advanced reasoning's request: every instinct as a tool with a query
/// field, the executor's own ask and done, the facts in the system
/// instruction, the exchanges and open webpages in the first turn, and the
/// wire shape the app sends.
@Suite struct PlannerTests {
    @Test func everyInstinctIsAToolWithAQueryFieldThenAskSayOpenLookAndDone() throws {
        let tools = Planner.tools(for: InstinctSpec.all)
        #expect(tools.map(\.name) == InstinctSpec.all.map(\.id) + ["ask", "say", "open", "look", "close", "done"])
        let recall = try #require(tools.first { $0.name == "recall" })
        #expect(recall.description.contains("In a plan it shows nothing: its result names what it found, by handle"))
        let open = try #require(tools.first { $0.name == "open" })
        #expect(open.parameters["required"]?.arrayValue?.first?.stringValue == "things")
        #expect(open.parameters["properties"]?["things"]?["type"]?.stringValue == "array")
        #expect(open.description.contains("shown together in a grid"))
        // The principle: a thing the listing holds is shown as itself, never retold.
        #expect(open.description.contains("is open with its handle, never a retelling of it in say"))
        #expect(Planner.sayTool.description.contains("Never to retell something the listing holds as a thing"))
        #expect(Planner.sayTool.description.contains("say is for a fact with no thing to show"))
        for tool in tools.dropLast(6) {
            let requiredNames = tool.parameters["required"]?.arrayValue?.compactMap { $0.stringValue }
            let required = try #require(requiredNames)
            #expect(required.contains("query"), "\(tool.name) takes a query")
            #expect(tool.parameters["properties"]?["query"]?["type"]?.stringValue == "string")
        }
        let remember = try #require(tools.first { $0.name == "remember" })
        #expect(remember.parameters["properties"]?["fact"]?["type"]?.stringValue == "string")
        #expect(remember.parameters["required"]?.arrayValue?.compactMap { $0.stringValue } == ["query", "fact"])
        #expect(remember.description.contains("Shows nothing"))
        let forget = try #require(tools.first { $0.name == "forget" })
        #expect(forget.description.contains("Asks the user itself"))
        #expect(forget.parameters["required"]?.arrayValue?.compactMap { $0.stringValue } == ["query"], "about is optional")
        let narrative = try #require(tools.first { $0.name == "narrative" })
        #expect(narrative.description.contains("Puts its result on the user's screen"))
        #expect(narrative.parameters["properties"]?["screen"] == nil, "an answer has no screen to choose: it goes to the bubble")
        // The two screens: a page-opening tool says whose screen, Jarbits's by default.
        let web = try #require(tools.first { $0.name == "web_results" })
        #expect(web.description.contains("Opens its page on my screen, where only I read it; on the user's screen when screen is user"))
        #expect(web.parameters["properties"]?["screen"]?["enum"]?.arrayValue?.compactMap { $0.stringValue } == ["mine", "user"])
        #expect(web.parameters["required"]?.arrayValue?.compactMap { $0.stringValue } == ["query", "screen"], "every page step says whose screen")
        #expect(Planner.screenField.description.contains("Every page step says which"))
        for name in ["image", "video", "map", "stock", "site"] {
            #expect(tools.first { $0.name == name }?.parameters["properties"]?["screen"] != nil, "\(name) opens a page")
        }
        for name in ["time", "notebook", "one_line", "recall", "remember"] {
            #expect(tools.first { $0.name == name }?.parameters["properties"]?["screen"] == nil, "\(name) opens no page")
        }
        #expect(InstinctSpec.spec(for: .webResults).arguments.fields.isEmpty, "the screen field lives on the tool, never on the spec, so Jev's questions do not change")
        #expect(open.description.contains("brought forward to the user's screen as it is, already loaded"))
        #expect(Planner.lookTool.description.contains("With thing left out, reads the newest page on my screen from this plan, else whatever is on the user's screen, page, note or answer"))
        #expect(Planner.sayTool.description.contains("(what I read on my screen included)"))
        let ask = try #require(tools.first { $0.name == "ask" })
        #expect(ask.parameters["required"]?.arrayValue?.compactMap { $0.stringValue } == ["question"])
        #expect(ask.parameters["properties"]?["options"]?["type"]?.stringValue == "array")
        #expect(tools.last?.parameters["properties"]?.objectValue?.isEmpty == true, "done takes nothing")
    }

    @Test func aPaidToolSaysTheDeviceConfirmsIt() {
        let paid = InstinctSpec(instinct: .webResults, sideEffects: .paid)
        #expect(Planner.describe(paid).contains("Costs money; the device confirms it with the user first."))
        let destructive = InstinctSpec(instinct: .webResults, sideEffects: .destructive)
        #expect(Planner.describe(destructive).contains("Cannot be undone; the device confirms it"))
    }

    @Test func theSystemInstructionCarriesTheRulesAndTheFacts() {
        let system = Planner.system(facts: ["Lorcan is vegetarian", "Lorcan lives in Austin"], context: .example, persona: .example)
        #expect(system.hasPrefix(Persona.example.speakerLine))
        #expect(system.contains("A fact you keep with remember is not said to anyone: it is written about Lorcan by name"))
        #expect(system.contains("Nothing you write outside a tool call is shown to anyone"))
        #expect(system.contains("call say with it"))
        #expect(system.contains("Never write an answer into a question"))
        #expect(system.contains("What Jarbits knows about Lorcan"))
        #expect(system.contains("There are two screens. Lorcan has theirs, where everything they see goes: narrative, one_line, time, notebook, say and open put their result there, each staying under the one before until the next request: so never say what a step has already shown (a note card says what was written, an answer answers), and after a step that showed something call done unless something is still missing (a caveat, a question). I have a screen of my own, where I read: web_results, map, stock, image, site, video open their page there unless screen is user, and nothing on my screen is seen by Lorcan."))
        #expect(system.contains("open brings it forward to Lorcan's screen as it is"))
        #expect(!system.contains("Show at most one thing"))
        #expect(system.contains("The listing tags each earlier thing of this session (p1, p2), each open webpage (w1, w2; what a browser calls tabs, open until Lorcan closes them), each note of my notebook (n1, n2) and each link in view on the screen (s1, s2)"))
        #expect(system.contains("never one you made up"))
        #expect(system.contains("in a note it is never written out: the handle in braces is the link"))
        #expect(Planner.describe(InstinctSpec.spec(for: .notebook)).contains("a link always goes into a note as the thing's handle in braces"))
        #expect(Planner.describe(InstinctSpec.spec(for: .notebook)).contains("Taking lines out is remove, by their numbers, never a rewrite of the rest"))
        #expect(Planner.describe(InstinctSpec.spec(for: .notebook)).contains("a line whose words stand in square brackets is a link"), "the planner can tell a link from a plain line")
        #expect(Planner.describe(InstinctSpec.spec(for: .notebook)).contains("a note emptied is a note with no lines, never a deleted one"))
        #expect(Planner.describe(InstinctSpec.spec(for: .notebook)).contains("ask which first, by their titles, and never write to both"), "two notes in view and neither named: a question, on the tool itself")
        #expect(Planner.fields(for: InstinctSpec.spec(for: .notebook)).contains { $0.name == "remove" }, "lines come out by number")
        #expect(InstinctSpec.spec(for: .notebook).arguments.fields.contains { $0.name == "remove" } == false, "on the tool, never on the spec: Jev's questions stay")
        #expect(Planner.fields(for: InstinctSpec.spec(for: .remember)).contains { $0.name == "remove" } == false)
        #expect(system.contains("never call remember for what the request says. Call remember for something lasting about Lorcan's own life that came out of an answer or of ask"))
        #expect(system.contains("ask does nothing itself: after a yes-like answer"), "an answer to ask is not a step done")
        #expect(Planner.doneTool.description.contains("A step that showed something has handled it; a line saying so adds nothing"), "a shown step is not narrated after")
        #expect(system.contains("never call it again with the same arguments"))
        #expect(system.contains("Call done when the request has been handled"))
        #expect(system.contains("- Lorcan is vegetarian\n- Lorcan lives in Austin"))
        #expect(system.contains("Locale: en_US"))
        #expect(Planner.system(facts: [], context: .example).contains("- nothing yet"))
    }

    @Test func everyNoteIsListedWholeAndNumbered() {
        let now = AnswerContext.example.now
        let trip = Note(title: "Trip", body: "## Groceries\n- [milk](https://m.com)\n\n## Packing\n- [ ] passport", created: now.addingTimeInterval(-86_400), edited: now.addingTimeInterval(-86_400))
        let input = Planner.input(query: "add eggs to the groceries", things: ThingTable(notes: [trip]), now: now)
        #expect(input.contains("In my notebook, every note (newest first):\n- n1: My note \"Trip\", edited yesterday:\n    1| ## Groceries\n    2| - [milk]\n    3| \n    4| ## Packing\n    5| - [ ] passport"), "a link as its bracketed title, blank lines numbered too")
        let notebook = Planner.tools(for: InstinctSpec.all).first { $0.name == "notebook" }
        #expect(notebook?.description.contains("text is the exact lines to add, in the marks of the lines around where they go, and after is the number of the line they follow") == true)
    }

    @Test func lookIsAToolWithARuleAndAResultShape() {
        let tools = Planner.tools(for: InstinctSpec.all)
        let look = tools.first { $0.name == "look" }
        #expect(look != nil && tools.last?.name == "done")
        #expect(look?.description.contains("when the request asks for what the listing or the screen block does not hold") == true)
        #expect(look?.description.contains("A note: its lines numbered (text), its links as handles (links)") == true, "look reads any thing")
        #expect(look?.parameters["properties"]?["thing"] != nil && look?.parameters["properties"]?["page"] == nil, "the field names any thing")
        #expect(Planner.looked(what: "text", text: "1| a", handles: [], in: ThingTable(), lead: "Lines of my note \"Trip\":") == "Lines of my note \"Trip\":\n1| a")
        #expect(look?.description.contains("a link (s2) is not an open thing: open it first") == true)
        #expect(Planner.system(facts: [], context: .example).contains("- look reads more of an open page than the screen block holds"))
        let link = ScreenItem(title: "Rick Steves' Europe: Lisbon", address: URL(string: "https://m.youtube.com/watch?v=abc")!)
        var things = ThingTable(items: [link])
        let minted = things.mint(items: [ScreenItem(title: "48 Hours in Lisbon", address: URL(string: "https://m.youtube.com/watch?v=ccc")!)])
        #expect(minted == ["s2"], "a look's links continue the screen's series")
        #expect(Planner.looked(what: "links", text: "\u{2026} more from link 41 of 90", handles: minted, in: things) == "Links on the page, in order:\n- s2: \"48 Hours in Lisbon\" \u{2192} https://m.youtube.com/watch?v=ccc\n\u{2026} more from link 41 of 90")
        #expect(Planner.looked(what: "text", text: "1| First paragraph.\n2| Second.", handles: [], in: things) == "1| First paragraph.\n2| Second.")
        #expect(Planner.looked(what: "tables", text: "", handles: [], in: things).hasPrefix("nothing of that kind on the page (tables)"))
    }

    @Test func aFailureIsTheFirstThingThePlannerReads() {
        let input = Planner.input(query: "open my packing list", things: ThingTable(), now: AnswerContext.example.now, lead: Planner.failureLead("I have no note the words mean in my notebook"))
        #expect(input.hasPrefix("Request: open my packing list\n\nTried first, and could not: I have no note the words mean in my notebook. Do what the request needs another way, or say so."))
        #expect(Planner.pickedLead(.notebook).hasPrefix("The classifier picked notebook with confidence; you run it, because it acts on things"))
        #expect(!Planner.input(query: "q", things: ThingTable(), now: AnswerContext.example.now).contains("Tried first"))
    }

    @Test func theFirstTurnHasTheRequestTheExchangesAndTheOpenWebpages() {
        let now = AnswerContext.example.now
        let hennessey = Webpage(kind: .page, address: URL(string: "https://www.hennesseyperformance.com/")!, title: "Hennessey Performance", query: "hennessey", opened: now.addingTimeInterval(-86_400))
        let webpages = [
            Webpage(kind: .search, address: QueryParser.searchURL(for: "venom f5 price"), query: "venom f5 price", opened: now.addingTimeInterval(-60)),
            hennessey,
        ]
        let input = Planner.input(
            query: "find a dealer near me for it",
            exchanges: [.search(query: "hennessey venom", term: "hennessey venom"), .page(query: "hennessey", title: "Hennessey Performance", address: URL(string: "https://www.hennesseyperformance.com/?utm_source=x")!)],
            webpages: webpages, now: now, calendar: Calendar(identifier: .gregorian)
        )
        #expect(input.hasPrefix("Request: find a dealer near me for it\n\nEarlier in this session (oldest first):\n- p1: "))
        #expect(input.contains("hennessey venom"))
        #expect(input.contains("- p2: Read \"Hennessey Performance\" (www.hennesseyperformance.com) (w2)"), "a page the user saw points at the open webpage it is")
        #expect(input.contains("Open webpages, newest first (what the user has open, kept until closed; open brings one forward, close closes; recall finds one by what it is about):\n- w1: A search for \"venom f5 price\", open since today\n- w2: A page open since yesterday (www.hennesseyperformance.com): \"Hennessey Performance\""))
        let things = ThingTable(exchanges: [], webpages: webpages)
        #expect(things.screenHandle(for: Screen(kind: .page, title: "Hennessey Performance", address: URL(string: "https://www.hennesseyperformance.com/?utm_source=x"))) == "w2", "the page on screen is the open webpage it is")
        let bare = Planner.input(query: "x", exchanges: [], webpages: [], now: now)
        #expect(bare == "Request: x\n\nIn my notebook: no notes yet.", "an empty notebook is said, so a write makes a note instead of asking which")
    }

    @Test func theScreenComesLastInTheFirstTurnWithItsLinksByHandleAndThePictureBeside() throws {
        let now = AnswerContext.example.now
        let items = [ScreenItem(title: "Lisbon in 4K", address: URL(string: "https://m.youtube.com/watch?v=def")!)]
        let screen = Screen(kind: .page, title: "YouTube", address: URL(string: "https://m.youtube.com/results?q=lisbon"), visible: "Lisbon in 4K\nRick Steves' Europe", items: items)
        let things = ThingTable(exchanges: [.page(query: "lisbon videos", title: "YouTube", address: URL(string: "https://m.youtube.com/results?q=lisbon")!)], items: items)
        let input = Planner.input(query: "open the first one", things: things, now: now, screen: screen)
        #expect(input.hasSuffix("\n\nOn screen, p1: the page \"YouTube\" at https://m.youtube.com/results?q=lisbon\nVisible now:\nLisbon in 4K\nRick Steves' Europe\nLinks in view, in order:\n- s1: \"Lisbon in 4K\" \u{2192} https://m.youtube.com/watch?v=def"), "the page on screen is named by the handle it already has")
        let trip = Note(title: "Trip", body: "- passport")
        let noteThings = ThingTable(exchanges: [.note(query: "open my trip note", title: "Trip", excerpt: "- passport", noteID: trip.id)], notes: [trip])
        let noteInput = Planner.input(query: "reorganize these notes", things: noteThings, now: now, screen: Screen(kind: .note, title: "Trip", visible: "- passport"), screenNoteID: trip.id)
        #expect(noteInput.contains("- p1: Opened my note \"Trip\" (n1)"), "the opened note points at the notebook's handle")
        #expect(noteInput.hasSuffix("\n\nOn screen, n1: my note \"Trip\" (its lines are listed under n1 above)"), "a note on screen is named once, by the notebook's handle, and not repeated")
        let ideas = Note(title: "Ideas", body: "- robot")
        let twoThings = ThingTable(exchanges: [.note(query: "open my trip note", title: "Trip", excerpt: "- passport", noteID: trip.id), .note(query: "pull up my ideas", title: "Ideas", excerpt: "- robot", noteID: ideas.id)], notes: [trip, ideas])
        let twoInput = Planner.input(query: "turn the bullets into checkboxes", things: twoThings, now: now, screen: Screen(kind: .note, title: "Trip", visible: "- passport"), screenNoteID: trip.id, bubble: Screen(kind: .note, title: "Ideas", visible: "- robot"), bubbleNoteID: ideas.id)
        #expect(twoInput.hasSuffix("\n\nOn screen, n1: my note \"Trip\" (its lines are listed under n1 above)\n\nIn the bubble, n2: my note \"Ideas\" (its lines are listed under n2 above)"), "the bubble is a second place in view")
        let sameThing = Planner.input(query: "q", things: twoThings, now: now, screen: Screen(kind: .note, title: "Trip", visible: "- passport"), screenNoteID: trip.id, bubble: Screen(kind: .note, title: "Trip", visible: "- passport"), bubbleNoteID: trip.id)
        #expect(!sameThing.contains("In the bubble"), "the same thing in both places is named once")
        #expect(Planner.system(facts: [], context: .example, persona: .example).contains("when one thing is in view, it is that thing, and asking would be a nuisance. Ask which, never whether"), "two things in view and an unnamed target get a question; one does not; whether is the device's")
        #expect(!noteInput.contains("Visible now"))
        let system = Planner.system(facts: [], context: .example, persona: .example)
        #expect(system.contains("The last block names what is on the screen by its handle"))
        #expect(system.contains("When the request itself carries the thing to write or keep"), "content in the sentence wins over the screen")
        #expect(system.contains("never ask Lorcan to say again what the listing already holds"))
        let spoken = Planner.input(query: "add it to my notes about my project", things: ThingTable(), now: now, spoken: "um add it to my, to my notes about my project")
        #expect(spoken.hasPrefix("Request: add it to my notes about my project\nAs spoken: \"um add it to my, to my notes about my project\"\n"), "the words as spoken ride beside the read words when they differ")
        #expect(!Planner.input(query: "q", things: ThingTable(), now: now, spoken: "q").contains("As spoken"))
        var write = Exchange.noteWrite(query: "add the rules", title: "Assistant project", heading: "Added to Assistant project", lines: "- answers should bold less\n- add subtitles", noteID: trip.id)
        write.asked = "make answers stricter about what they bold and add subtitles, and add it to my notes about my project"
        let worded = Planner.input(query: "no not that, I meant the rules", things: ThingTable(exchanges: [write], notes: [trip]), now: now)
        #expect(worded.contains("- p1: You asked \"make answers stricter about what they bold and add subtitles, and add it to my notes about my project\" → Added to Assistant project (my note \"Assistant project\"):\n    - answers should bold less\n    - add subtitles"), "the user's words and what was written are in view; got: \(worded)")
        #expect(system.contains("Never guess what a thing holds"), "what the listing does not show is one look away")
        #expect(system.contains("An effect in the world no tool of yours produces"), "an effect with no tool is said at once")
        #expect(system.contains("judge progress, not attempts"), "a step that gained nothing is the moment to say why, and keep checking")
        #expect(system.contains("after saying what you could not do, when you have checked what was worth checking"))
        #expect(Planner.sayTool.description.contains("or to tell the user what you could not do and what would, while you keep checking"))
        #expect(system.contains("each link in view on the screen (s1, s2)"))
        #expect(system.contains(Screen.rule) && system.contains(Screen.pictureRule))
        #expect(system.contains("open shows it as itself") && system.contains("Never retell a thing you could show."))
        #expect(Planner.firstTurn("words", picture: nil) == .userText("words"))
        #expect(Planner.firstTurn("words", picture: Data()) == .userText("words"))
        let picture = Data([0xFF, 0xD8, 0xFF])
        let turn = Planner.firstTurn("words", picture: picture)
        #expect(turn == .userParts([.text("words"), .image(picture, mimeType: "image/jpeg")]))
        let bundle = PlanBundle(query: "q", exchanges: [], facts: [], tools: [], context: .example, screen: screen)
        let body = try Planner.request(bundle: bundle, transcript: [turn]).jsonData()
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let steps = try #require(json["input"] as? [[String: Any]])
        let content = try #require(steps[0]["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "text" && content[0]["text"] as? String == "words")
        #expect(content[1]["type"] as? String == "image" && content[1]["mime_type"] as? String == "image/jpeg" && content[1]["data"] as? String == picture.base64EncodedString(), "Google's image part: type, data, mime_type")
    }

    @Test func theRequestIsOneWholeBodyCallWithEveryToolAndToolChoiceAny() throws {
        let bundle = PlanBundle(query: "q", exchanges: [], facts: ["f"], tools: Planner.tools(for: InstinctSpec.all), context: .example)
        let transcript: [InteractionStep] = [.userText(Planner.input(query: "q", exchanges: [], webpages: [], now: AnswerContext.example.now))]
        let request = Planner.request(bundle: bundle, transcript: transcript)
        #expect(request.model == Planner.model)
        #expect(request.stream == false)
        #expect(request.toolChoice == .any)
        #expect(request.tools.count == InstinctSpec.all.count + 6)
        #expect(request.tools.suffix(6).map(\.name) == ["ask", "say", "open", "look", "close", "done"])
        #expect(Planner.sayTool.parameters["required"]?.arrayValue?.first?.stringValue == "text")
        #expect(request.maxOutputTokens == Planner.maxOutputTokens)
        #expect(request.thinkingLevel == Planner.thinkingLevel)
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        #expect(json["model"] as? String == "gemini-3.1-flash-lite")
        #expect(json["stream"] as? Bool == false)
        #expect(json["store"] as? Bool == false)
        #expect((json["tools"] as? [[String: Any]])?.count == InstinctSpec.all.count + 6)
        let config = try #require(json["generation_config"] as? [String: Any])
        #expect(config["tool_choice"] as? String == "any")
        #expect(config["thinking_level"] as? String == "high", "accuracy over speed: the planner thinks")
        let input = try #require(json["input"] as? [[String: Any]])
        #expect(input.count == 1)
        #expect((json["system_instruction"] as? String)?.contains("- f") == true)
    }

    @Test func aRoundReplaysTheModelStepsAndTheResults() throws {
        let bundle = PlanBundle(query: "q", exchanges: [], facts: [], tools: [], context: .example)
        let call = FunctionCall(id: "call_1", name: "remember", arguments: ["query": "I'm vegetarian", "fact": "I'm vegetarian"])
        let transcript: [InteractionStep] = [
            .userText("Request: q"),
            .verbatim(["type": "function_call", "id": "call_1", "name": "remember", "arguments": ["query": "I'm vegetarian", "fact": "I'm vegetarian"]]),
            .functionResult(FunctionResult(callID: call.id, name: call.name, text: "done")),
        ]
        let json = try #require(JSONSerialization.jsonObject(with: Planner.request(bundle: bundle, transcript: transcript).jsonData()) as? [String: Any])
        let input = try #require(json["input"] as? [[String: Any]])
        #expect(input.count == 3)
        #expect(input[1]["type"] as? String == "function_call")
        #expect(input[2]["type"] as? String == "function_result")
        #expect(input[2]["call_id"] as? String == "call_1")
    }

    @Test func thePlannerIsTheExtractorsModelAtTheLitePrice() {
        #expect(Planner.model == GeminiClient.defaultModel)
        #expect(Planner.model.contains("lite"), "GeminiPricing.cost bills a Lite model at the Lite rates")
        #expect(GeminiPricing.cost(AnswerUsage(inputTokens: 2600, outputTokens: 40, thoughtTokens: 0), model: Planner.model) < 0.001, "a round is well under a tenth of a cent")
    }
}
