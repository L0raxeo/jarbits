import Foundation
import Routing
import Testing
@testable import Answers

@Suite struct InteractionResponseTests {
    /// A whole-body reply with text and two calls, in the shape Google documents.
    static let planBody = """
    {"id":"int_2","status":"completed","model":"gemini-3.1-flash-lite","steps":[{"type":"thought_summary","content":[{"type":"text","text":"…"}],"signature":"abc"},{"type":"model_output","content":[{"type":"text","text":"{\\"temperature\\":"},{"type":"text","text":"68}"}]},{"type":"function_call","id":"call_1","name":"narrative","arguments":{"query":"a vegetarian dinner","count":2}},{"type":"function_call","id":"call_2","name":"done","arguments":"{\\"reason\\":\\"shown\\"}"}],"usage":{"total_input_tokens":300,"total_output_tokens":20,"total_thought_tokens":5,"total_tokens":325}}
    """

    @Test func stepsAreReadInOrderAndKeptVerbatim() throws {
        let interaction = try InteractionResponse.parse(Data(Self.planBody.utf8))
        #expect(interaction.id == "int_2")
        #expect(interaction.status == "completed")
        #expect(interaction.model == "gemini-3.1-flash-lite")
        #expect(interaction.usable)
        #expect(interaction.steps.count == 4)
        #expect(interaction.steps[0] == .other(type: "thought_summary"))
        #expect(interaction.text == "{\"temperature\":68}", "text parts joined")
        #expect(interaction.functionCalls == [
            FunctionCall(id: "call_1", name: "narrative", arguments: ["query": "a vegetarian dinner", "count": 2]),
            FunctionCall(id: "call_2", name: "done", arguments: ["reason": "shown"]),
        ], "arguments as an object or as JSON text")
        #expect(interaction.usage == AnswerUsage(inputTokens: 300, outputTokens: 20, thoughtTokens: 5))
        #expect(interaction.rawSteps.count == 4)
        #expect(interaction.rawSteps[0]["signature"]?.stringValue == "abc", "the unknown step is kept whole for replay")
        #expect(interaction.rawSteps[2]["name"]?.stringValue == "narrative")
    }

    @Test func aWrappedBodyAndAMissingStatusRead() throws {
        let wrapped = #"{"interaction":{"steps":[{"type":"model_output","content":[{"type":"text","text":"hi"}]}]}}"#
        let interaction = try InteractionResponse.parse(Data(wrapped.utf8))
        #expect(interaction.text == "hi")
        #expect(interaction.status == "completed")
        #expect(interaction.usage == nil)
        #expect(interaction.functionCalls.isEmpty)
    }

    @Test func errorsThrowAndAFailedStatusIsNotUsable() {
        #expect(throws: GeminiError.response("quota exceeded")) {
            try InteractionResponse.parse(Data(#"{"error":{"code":429,"message":"quota exceeded"}}"#.utf8))
        }
        #expect(throws: GeminiError.response("bad tool")) {
            try InteractionResponse.parse(Data(#"{"id":"x","status":"failed","errors":[{"message":"bad tool"}],"steps":[]}"#.utf8))
        }
        #expect(throws: GeminiError.self) { try InteractionResponse.parse(Data("not json".utf8)) }
        let failed = try? InteractionResponse.parse(Data(#"{"id":"x","status":"failed","steps":[]}"#.utf8))
        #expect(failed?.usable == false)
        let waiting = try? InteractionResponse.parse(Data(#"{"id":"x","status":"requires_action","steps":[]}"#.utf8))
        #expect(waiting?.usable == true)
    }
}
