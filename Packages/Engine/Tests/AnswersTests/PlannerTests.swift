import Foundation
import Testing
@testable import Answers
@testable import Engine

/// Advanced reasoning's request: every instinct as a tool with a query
/// field, the executor's own ask and done, the facts in the system
/// instruction, the exchanges and memories in the first turn, and the
/// wire shape the app sends.
@Suite struct PlannerTests {
    @Test func everyInstinctIsAToolWithAQueryFieldThenAskAndDone() throws {
        let tools = Planner.tools(for: InstinctSpec.all)
        #expect(tools.map(\.name) == InstinctSpec.all.map(\.id) + ["ask", "done"])
        for tool in tools.dropLast(2) {
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
        #expect(narrative.description.contains("Puts its result on screen"))
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
        let system = Planner.system(facts: ["I'm vegetarian", "I live in Austin"], context: .example)
        #expect(system.contains("nothing you write is shown to anyone"))
        #expect(system.contains("Show at most one thing, as the last step: web_results, narrative, map, stock, one_line, recall, image, site, video, time each put a result on screen"))
        #expect(system.contains("call remember with it next"))
        #expect(system.contains("never call it again with the same arguments"))
        #expect(system.contains("Call done when the request has been handled"))
        #expect(system.contains("- I'm vegetarian\n- I live in Austin"))
        #expect(system.contains("Locale: en_US"))
        #expect(Planner.system(facts: [], context: .example).contains("- nothing yet"))
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
        #expect(input.hasPrefix("Request: find a dealer near me for it\n\nEarlier in this session (oldest first):\n- "))
        #expect(input.contains("hennessey venom"))
        #expect(input.contains("Seen in this app before, that the request may mean (newest first):\n- A page from yesterday (www.hennesseyperformance.com): \"Hennessey Performance\"\n- An answer from today: \"what is a venom f5\""))
        let bare = Planner.input(query: "x", exchanges: [], memories: [], now: now)
        #expect(bare == "Request: x")
    }

    @Test func theRequestIsOneWholeBodyCallWithEveryToolAndToolChoiceAny() throws {
        let bundle = PlanBundle(query: "q", exchanges: [], facts: ["f"], memories: [], tools: Planner.tools(for: InstinctSpec.all), context: .example)
        let transcript: [InteractionStep] = [.userText(Planner.input(query: "q", exchanges: [], memories: [], now: AnswerContext.example.now))]
        let request = Planner.request(bundle: bundle, transcript: transcript)
        #expect(request.model == Planner.model)
        #expect(request.stream == false)
        #expect(request.toolChoice == .any)
        #expect(request.tools.count == InstinctSpec.all.count + 2)
        #expect(request.maxOutputTokens == Planner.maxOutputTokens)
        #expect(request.thinkingLevel == Planner.thinkingLevel)
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        #expect(json["model"] as? String == "gemini-3.1-flash-lite")
        #expect(json["stream"] as? Bool == false)
        #expect(json["store"] as? Bool == false)
        #expect((json["tools"] as? [[String: Any]])?.count == InstinctSpec.all.count + 2)
        let config = try #require(json["generation_config"] as? [String: Any])
        #expect(config["tool_choice"] as? String == "any")
        #expect(config["thinking_level"] as? String == "minimal", "the extractor's level; gemini-3.8-flash refused it and took 11 s at low (2026-10-27)")
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
