import Foundation
import Engine
import Testing
@testable import Answers

@Suite struct RequestTests {
    @Test func bodyMatchesTheDocumentedShape() throws {
        let request = AnswerPrompt.request(format: .oneLine, query: "capital of peru", context: .example)
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])

        #expect(json["model"] as? String == GeminiClient.defaultModel)
        #expect(json["stream"] as? Bool == true)
        #expect(json["store"] as? Bool == false)
        #expect(json["tools"] == nil, "no grounding: Google's terms would require their Search Suggestions bar")
        let generation = try #require(json["generation_config"] as? [String: Any])
        #expect(generation["thinking_level"] as? String == "minimal")
        #expect(generation["max_output_tokens"] as? Int == AnswerPrompt.maxOutputTokens(for: .oneLine))
        #expect(json["system_instruction"] as? String == AnswerPrompt.system(for: .oneLine))
        #expect((json["input"] as? String)?.hasPrefix("Query: capital of peru\n") == true)
    }

    @Test func keyOrderIsStable() throws {
        let body = String(decoding: try AnswerPrompt.request(format: .narrative, query: "q", context: .example).jsonData(), as: UTF8.self)
        let order = ["\"model\"", "\"system_instruction\"", "\"input\"", "\"generation_config\"", "\"stream\"", "\"store\""]
        let positions = order.map { body.range(of: $0)!.lowerBound }
        #expect(positions == positions.sorted())
    }

    @Test func theNewFieldsAtTheirDefaultsLeaveTheFirstVersionsBytesUnchanged() throws {
        let request = AnswerPrompt.request(format: .narrative, query: "q", context: .example)
        let explicit = InteractionRequest(
            model: request.model, systemInstruction: request.systemInstruction, input: request.input, history: [],
            maxOutputTokens: request.maxOutputTokens, thinkingLevel: "minimal", stream: true, tools: [], toolChoice: nil, outputSchema: nil, transcript: nil
        )
        #expect(try explicit.jsonData() == request.jsonData())
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        #expect(Set(json.keys) == ["model", "system_instruction", "input", "generation_config", "stream", "store"])
        let generation = try #require(json["generation_config"] as? [String: Any])
        #expect(Set(generation.keys) == ["thinking_level", "max_output_tokens"])
    }

    @Test func toolsRenderAfterTheInputAndTheToolChoiceInsideGenerationConfig() throws {
        var request = AnswerPrompt.request(format: .narrative, query: "q", context: .example)
        request.tools = [ToolDeclaration(name: "narrative", description: "Answer in a paragraph.", parameters: ["type": "object", "properties": ["query": ["type": "string"]], "required": ["query"]])]
        request.toolChoice = .any
        let body = String(decoding: try request.jsonData(), as: UTF8.self)
        let order = ["\"model\"", "\"system_instruction\"", "\"input\"", "\"tools\"", "\"generation_config\"", "\"tool_choice\"", "\"stream\"", "\"store\""]
        let positions = order.map { body.range(of: $0)!.lowerBound }
        #expect(positions == positions.sorted())
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        let tools = try #require(json["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "function")
        #expect(tools[0]["name"] as? String == "narrative")
        #expect(tools[0]["description"] as? String == "Answer in a paragraph.")
        #expect((tools[0]["parameters"] as? [String: Any])?["type"] as? String == "object")
        #expect(((tools[0]["parameters"] as? [String: Any])?["required"] as? [String]) == ["query"])
        #expect((json["generation_config"] as? [String: Any])?["tool_choice"] as? String == "any")
        request.toolChoice = .only(["narrative", "done"])
        let restricted = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        let choice = try #require(((restricted["generation_config"] as? [String: Any])?["tool_choice"] as? [String: Any])?["allowed_tools"] as? [String: Any])
        #expect(choice["mode"] as? String == "any")
        #expect(choice["tools"] as? [String] == ["narrative", "done"])
    }

    @Test func aSchemaBecomesTheResponseFormatAndStreamCanBeOff() throws {
        var request = AnswerPrompt.request(format: .oneLine, query: "set the thermostat to 68", context: .example)
        request.stream = false
        request.outputSchema = ["type": "object", "properties": ["temperature": ["type": "integer"]], "required": ["temperature"], "additionalProperties": false]
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        #expect(json["stream"] as? Bool == false)
        let format = try #require(json["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "text")
        #expect(format["mime_type"] as? String == "application/json")
        #expect((format["schema"] as? [String: Any])?["type"] as? String == "object")
        #expect(((format["schema"] as? [String: Any])?["required"] as? [String]) == ["temperature"])
        #expect(json["tools"] == nil)
        let body = String(decoding: try request.jsonData(), as: UTF8.self)
        let order = ["\"generation_config\"", "\"response_format\"", "\"stream\"", "\"store\""]
        let positions = order.map { body.range(of: $0)!.lowerBound }
        #expect(positions == positions.sorted())
    }

    @Test func aTranscriptReplacesTheInputAndReplaysModelStepsVerbatim() throws {
        var request = AnswerPrompt.request(format: .narrative, query: "ignored", context: .example, history: [AnswerTurn(query: "also", answer: "ignored")])
        let call: JSONValue = ["type": "function_call", "id": "call_1", "name": "narrative", "arguments": ["query": "a vegetarian dinner"], "thought_signature": "sig==", "extra": ["nested": [1, 2]]]
        request.transcript = [
            .userText("Request: remember I'm vegetarian, then suggest dinner"),
            .verbatim(call),
            .functionResult(FunctionResult(callID: "call_1", name: "narrative", text: "shown")),
            .modelText("ok"),
        ]
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        let steps = try #require(json["input"] as? [[String: Any]])
        #expect(steps.map { $0["type"] as? String } == ["user_input", "function_call", "function_result", "model_output"])
        #expect(try JSONValue(any: steps[1]) == call, "the model's step goes back exactly as it came")
        #expect(steps[2]["call_id"] as? String == "call_1")
        #expect(steps[2]["name"] as? String == "narrative")
        #expect(((steps[2]["result"] as? [[String: Any]])?.first?["text"] as? String) == "shown")
        #expect(((steps[3]["content"] as? [[String: Any]])?.first?["text"] as? String) == "ok")
        #expect(json["store"] as? Bool == false)
    }

    @Test func withoutHistoryTheInputIsAString() throws {
        let request = AnswerPrompt.request(format: .narrative, query: "q", context: .example)
        #expect(request.history.isEmpty)
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        #expect(json["input"] is String)
    }

    @Test func historyBecomesSteps() throws {
        let history = [
            AnswerTurn(query: "how do you make hot chocolate", answer: "You **heat milk** and whisk in cocoa."),
            AnswerTurn(query: "why low heat?", answer: "Milk ==scorches== above a simmer."),
        ]
        let request = AnswerPrompt.request(format: .narrative, query: "and with water?", context: .example, history: history)
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        let steps = try #require(json["input"] as? [[String: Any]])
        #expect(steps.count == 5)
        #expect(steps.map { $0["type"] as? String } == ["user_input", "model_output", "user_input", "model_output", "user_input"])
        func text(_ step: [String: Any]) -> String? {
            (step["content"] as? [[String: Any]])?.first?["text"] as? String
        }
        #expect((steps[0]["content"] as? [[String: Any]])?.first?["type"] as? String == "text")
        #expect(text(steps[0]) == "how do you make hot chocolate", "earlier queries go bare")
        #expect(text(steps[1]) == "You **heat milk** and whisk in cocoa.")
        #expect(text(steps[3]) == "Milk ==scorches== above a simmer.", "markup goes back as it was shown")
        #expect(text(steps[4])?.hasPrefix("Query: and with water?\n") == true, "only the last turn carries the context block")
        #expect(json["store"] as? Bool == false)
    }

    @Test func theWholeHistoryGoes() throws {
        let history = (0..<10).map { AnswerTurn(query: "q\($0)", answer: "a\($0)") }
        let request = AnswerPrompt.request(format: .narrative, query: "q10", context: .example, history: history)
        #expect(request.history == history)
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        #expect((json["input"] as? [Any])?.count == 2 * history.count + 1)
    }

    @Test func keyOrderIsStableWithHistory() throws {
        let request = AnswerPrompt.request(format: .narrative, query: "q", context: .example, history: [AnswerTurn(query: "a", answer: "b")])
        let body = String(decoding: try request.jsonData(), as: UTF8.self)
        let order = ["\"model\"", "\"system_instruction\"", "\"input\"", "\"generation_config\"", "\"stream\"", "\"store\""]
        let positions = order.map { body.range(of: $0)!.lowerBound }
        #expect(positions == positions.sorted())
    }

    @Test func eachFormatHasItsOwnRulesAndBudget() {
        let narrative = AnswerPrompt.system(for: .narrative)
        let oneLine = AnswerPrompt.system(for: .oneLine)
        #expect(narrative != oneLine)
        #expect(narrative.contains("Open with the most immediate, simple answer"))
        #expect(narrative.contains("There is no target length"))
        #expect(!narrative.contains("two to four"), "no word or paragraph count")
        #expect(Instinct.narrative.criterion.examples.contains("whats isi in ipe"))
        #expect(Instinct.oneLine.criterion.notFor.contains("definitions"))
        #expect(narrative.contains("no access to the web"))
        #expect(narrative.contains("Never say when your knowledge ends"), "no cutoff disclaimer in a narrative")
        #expect(!narrative.contains("may be out of date, then"))
        #expect(narrative.contains("Earlier turns of this conversation"), "a continued narrative reads as a reply")
        #expect(narrative.contains("each answer in a conversation has its own"))
        #expect(oneLine.contains("whether a person is alive"))
        #expect(oneLine.contains("one line only"))
        #expect(oneLine.contains("Never more than twelve words"))
        #expect(oneLine.contains("Earlier turns of this conversation"), "a one-line reply can continue a thread")
        #expect(narrative.contains("Earlier turns of this conversation"))
        #expect(oneLine.contains("reply with exactly: \(AnswerPrompt.liveDataMarker)"))
        #expect(AnswerPrompt.maxOutputTokens(for: .narrative) > AnswerPrompt.maxOutputTokens(for: .oneLine))
    }

    @Test func earlierExchangesGoInTheContextBlockOnly() throws {
        let earlier: [Exchange] = [
            .search(query: "brasil weather", term: "brasil weather"),
            .page(query: "brasil weather", title: "Weather in Brasília", address: URL(string: "https://weather.com/br")!),
            .answer(query: "capital of peru", text: "==Lima=="),
            .picture(query: "eiffel tower", subject: "eiffel tower"),
        ]
        let request = AnswerPrompt.request(format: .narrative, query: "how big is it", context: .example, earlier: earlier)
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        let input = try #require(json["input"] as? String, "no history: the input stays a string")
        #expect(input.hasPrefix("Query: how big is it\n"))
        #expect(input.contains("- Locale: en_US\n\nEarlier in this session (oldest first; the query may lean on them, but answer only the query):\n"), "after the context block")
        #expect(input.hasSuffix("- Searched \"brasil weather\"\n- Read \"Weather in Brasília\" (weather.com)\n- Asked \"capital of peru\" and got: ==Lima==\n- Looked at a picture of \"eiffel tower\""))
        #expect(!AnswerPrompt.input(query: "x", context: .example).contains("Earlier in this session"), "nothing added without exchanges")
        let withHistory = AnswerPrompt.request(format: .narrative, query: "why?", context: .example, history: [AnswerTurn(query: "q", answer: "a")], earlier: Array(earlier.prefix(1)))
        let steps = try #require(JSONSerialization.jsonObject(with: withHistory.jsonData()) as? [String: Any])["input"] as? [[String: Any]]
        #expect(steps?.count == 3, "the exchanges add no steps")
        #expect(((steps?.last?["content"] as? [[String: Any]])?.first?["text"] as? String)?.contains("- Searched \"brasil weather\"") == true, "they ride in the last step")
    }

    @Test func factsFollowTheContextAndTheExchangesAndThePromptsNameTheBlock() throws {
        let input = AnswerPrompt.input(query: "give me a dinner recipe", context: .example, earlier: [.search(query: "dinner", term: "dinner ideas")], facts: ["I'm vegetarian", "I hate cilantro"])
        #expect(input.hasSuffix("- Searched \"dinner ideas\"\n\nWhat you know about the user (told earlier; let it shape the answer when it bears on it, never repeat it or say you were told):\n- I'm vegetarian\n- I hate cilantro"))
        #expect(!AnswerPrompt.input(query: "x", context: .example).contains("What you know about the user"), "nothing added without facts")
        let request = AnswerPrompt.request(format: .oneLine, query: "q", context: .example, facts: ["I use metric units"])
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        #expect((json["input"] as? String)?.hasSuffix("- I use metric units") == true)
        #expect(AnswerPrompt.system(for: .narrative).contains("What you know about the user"))
        #expect(AnswerPrompt.system(for: .oneLine).contains("What you know about the user"))
        #expect(AnswerPrompt.system(for: .narrative).contains("never list them back"))
    }

    @Test func contextCarriesDateZoneAndLocale() {
        let input = AnswerPrompt.input(query: "what's the time in costa rica", context: .example)
        #expect(input.contains("- Date and time: Wednesday 21 October 2026, 11:26 (America/Chicago)"), "got: \(input)")
        #expect(input.contains("- Locale: en_US"))
        #expect(!input.contains("location"))
        #expect(input.contains("- Your knowledge ends around January 2025, about 21 months before this date."), "got: \(input)")

        var atCutoff = AnswerContext.example
        atCutoff.now = Date(timeIntervalSince1970: 1_736_000_000)   // 4 January 2025
        #expect(AnswerPrompt.input(query: "x", context: atCutoff).contains("about 0 months before"))
    }
}
