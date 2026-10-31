import Foundation
import Testing
@testable import Answers
@testable import Engine

/// Advanced reasoning's request: every instinct as a tool with a query
/// field, the executor's own ask and done, the facts in the system
/// instruction, the exchanges and memories in the first turn, and the
/// wire shape the app sends.
@Suite struct PlannerTests {
    @Test func everyInstinctIsAToolWithAQueryFieldThenAskSayOpenLookAndDone() throws {
        let tools = Planner.tools(for: InstinctSpec.all)
        #expect(tools.map(\.name) == InstinctSpec.all.map(\.id) + ["ask", "say", "open", "look", "done"])
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
        for tool in tools.dropLast(5) {
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
        #expect(Planner.lookTool.description.contains("Reads the page on my screen when a step of this plan opened one (the newest), else the page on the user's screen"))
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
        #expect(system.hasPrefix(Persona.example.identityLine))
        #expect(system.contains("Nothing you write outside a tool call is shown to anyone"))
        #expect(system.contains("call say with it"))
        #expect(system.contains("Never write an answer into a question"))
        #expect(system.contains("What Jarbits knows about Lorcan"))
        #expect(system.contains("There are two screens. Lorcan has theirs, where everything they see goes: narrative, one_line, time, notebook, say and open put their result there, and a later one replaces the earlier: end on what Lorcan should see. I have a screen of my own, where I read: web_results, map, stock, image, site, video open their page there unless screen is user, and nothing on my screen is seen by Lorcan."))
        #expect(system.contains("open brings it forward to Lorcan's screen as it is"))
        #expect(!system.contains("Show at most one thing"))
        #expect(system.contains("The listing tags each earlier thing of this session (p1, p2), each memory (m1, m2), each note of my notebook (n1, n2) and each link in view on the screen (s1, s2)"))
        #expect(system.contains("never one you made up"))
        #expect(system.contains("call remember with it next"))
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
        #expect(input.contains("In my notebook, every note (newest first):\n- n1: My note \"Trip\", edited yesterday:\n    1| ## Groceries\n    2| - milk\n    3| \n    4| ## Packing\n    5| - [ ] passport"), "links as titles, blank lines numbered too")
        let notebook = Planner.tools(for: InstinctSpec.all).first { $0.name == "notebook" }
        #expect(notebook?.description.contains("text is the exact lines to add, in the marks of the lines around where they go, and after is the number of the line they follow") == true)
    }

    @Test func lookIsAToolWithARuleAndAResultShape() {
        let tools = Planner.tools(for: InstinctSpec.all)
        let look = tools.first { $0.name == "look" }
        #expect(look != nil && tools.last?.name == "done")
        #expect(look?.description.contains("when the request asks for what the screen block does not hold") == true)
        #expect(look?.description.contains("a link (s2) is not an open page: open it first") == true)
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

    @Test func theFirstTurnHasTheRequestTheExchangesAndTheMemories() {
        let now = AnswerContext.example.now
        let memories = [
            MemoryRecord(date: now.addingTimeInterval(-86_400), kind: .page, query: "hennessey", title: "Hennessey Performance", url: URL(string: "https://www.hennesseyperformance.com/")),
            MemoryRecord(date: now.addingTimeInterval(-60), kind: .narrative, query: "what is a venom f5", text: "A car."),
        ]
        let input = Planner.input(
            query: "find a dealer near me for it",
            exchanges: [.search(query: "hennessey venom", term: "hennessey venom")],
            memories: memories, now: now, calendar: Calendar(identifier: .gregorian)
        )
        #expect(input.hasPrefix("Request: find a dealer near me for it\n\nEarlier in this session (oldest first):\n- p1: "))
        #expect(input.contains("hennessey venom"))
        #expect(input.contains("Seen in this app before, the newest (recall finds the rest):\n- m1: A page from yesterday (www.hennesseyperformance.com): \"Hennessey Performance\"\n- m2: An answer from today: \"what is a venom f5\""))
        let bare = Planner.input(query: "x", exchanges: [], memories: [], now: now)
        #expect(bare == "Request: x\n\nIn my notebook: no notes yet.", "an empty notebook is said, so a write makes a note instead of asking which")
    }

    @Test func theScreenComesLastInTheFirstTurnWithItsLinksByHandleAndThePictureBeside() throws {
        let now = AnswerContext.example.now
        let items = [ScreenItem(title: "Lisbon in 4K", address: URL(string: "https://m.youtube.com/watch?v=def")!)]
        let screen = Screen(kind: .page, title: "YouTube", address: URL(string: "https://m.youtube.com/results?q=lisbon"), visible: "Lisbon in 4K\nRick Steves' Europe", items: items)
        let things = ThingTable(exchanges: [.page(query: "lisbon videos", title: "YouTube", address: URL(string: "https://m.youtube.com/results?q=lisbon")!)], items: items)
        let input = Planner.input(query: "open the first one", things: things, now: now, screen: screen)
        #expect(input.hasSuffix("\n\nOn screen: the page \"YouTube\" at https://m.youtube.com/results?q=lisbon\nVisible now:\nLisbon in 4K\nRick Steves' Europe\nLinks in view, in order:\n- s1: \"Lisbon in 4K\" \u{2192} https://m.youtube.com/watch?v=def"))
        let system = Planner.system(facts: [], context: .example, persona: .example)
        #expect(system.contains("each link in view on the screen (s1, s2)"))
        #expect(system.contains(Screen.rule) && system.contains(Screen.pictureRule))
        #expect(system.contains("open shows it as itself") && system.contains("Never retell a thing you could show."))
        #expect(Planner.firstTurn("words", picture: nil) == .userText("words"))
        #expect(Planner.firstTurn("words", picture: Data()) == .userText("words"))
        let picture = Data([0xFF, 0xD8, 0xFF])
        let turn = Planner.firstTurn("words", picture: picture)
        #expect(turn == .userParts([.text("words"), .image(picture, mimeType: "image/jpeg")]))
        let bundle = PlanBundle(query: "q", exchanges: [], facts: [], memories: [], tools: [], context: .example, screen: screen)
        let body = try Planner.request(bundle: bundle, transcript: [turn]).jsonData()
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let steps = try #require(json["input"] as? [[String: Any]])
        let content = try #require(steps[0]["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "text" && content[0]["text"] as? String == "words")
        #expect(content[1]["type"] as? String == "image" && content[1]["mime_type"] as? String == "image/jpeg" && content[1]["data"] as? String == picture.base64EncodedString(), "Google's image part: type, data, mime_type")
    }

    @Test func theRequestIsOneWholeBodyCallWithEveryToolAndToolChoiceAny() throws {
        let bundle = PlanBundle(query: "q", exchanges: [], facts: ["f"], memories: [], tools: Planner.tools(for: InstinctSpec.all), context: .example)
        let transcript: [InteractionStep] = [.userText(Planner.input(query: "q", exchanges: [], memories: [], now: AnswerContext.example.now))]
        let request = Planner.request(bundle: bundle, transcript: transcript)
        #expect(request.model == Planner.model)
        #expect(request.stream == false)
        #expect(request.toolChoice == .any)
        #expect(request.tools.count == InstinctSpec.all.count + 5)
        #expect(request.tools.suffix(5).map(\.name) == ["ask", "say", "open", "look", "done"])
        #expect(Planner.sayTool.parameters["required"]?.arrayValue?.first?.stringValue == "text")
        #expect(request.maxOutputTokens == Planner.maxOutputTokens)
        #expect(request.thinkingLevel == Planner.thinkingLevel)
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        #expect(json["model"] as? String == "gemini-3.1-flash-lite")
        #expect(json["stream"] as? Bool == false)
        #expect(json["store"] as? Bool == false)
        #expect((json["tools"] as? [[String: Any]])?.count == InstinctSpec.all.count + 5)
        let config = try #require(json["generation_config"] as? [String: Any])
        #expect(config["tool_choice"] as? String == "any")
        #expect(config["thinking_level"] as? String == "high", "accuracy over speed: the planner thinks")
        let input = try #require(json["input"] as? [[String: Any]])
        #expect(input.count == 1)
        #expect((json["system_instruction"] as? String)?.contains("- f") == true)
    }

    @Test func aRoundReplaysTheModelStepsAndTheResults() throws {
        let bundle = PlanBundle(query: "q", exchanges: [], facts: [], memories: [], tools: [], context: .example)
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
