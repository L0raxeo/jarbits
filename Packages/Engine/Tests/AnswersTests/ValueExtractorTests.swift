import Foundation
import Engine
import Testing
@testable import Answers

/// The request alone; the calls over the mock transport live with the
/// other Gemini client tests, which own that transport.
@Suite struct ValueExtractorTests {
    static let thermostat = ArgumentSchema(fields: [
        .init(name: "temperature", kind: .integer, description: "the degrees asked for"),
        .init(name: "room", kind: .text, description: "which room", required: false),
    ]).jsonSchema()

    @Test func theRequestIsOneWholeBodyCallWithTheSchema() throws {
        let request = ValueExtractor.request(query: "set it to 68 in the bedroom", exchanges: [.search(query: "thermostat", term: "thermostat")], schema: Self.thermostat)
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        #expect(json["model"] as? String == GeminiClient.defaultModel)
        #expect(json["stream"] as? Bool == false)
        #expect(json["store"] as? Bool == false)
        #expect(json["tools"] == nil)
        let generation = try #require(json["generation_config"] as? [String: Any])
        #expect(generation["thinking_level"] as? String == "minimal")
        #expect(generation["max_output_tokens"] as? Int == ValueExtractor.maxOutputTokens)
        let format = try #require(json["response_format"] as? [String: Any])
        #expect(format["mime_type"] as? String == "application/json")
        #expect(((format["schema"] as? [String: Any])?["required"] as? [String]) == ["temperature"])
        #expect(json["system_instruction"] as? String == ValueExtractor.system)
        #expect(json["input"] as? String == "Earlier: Searched \"thermostat\"\nRequest: set it to 68 in the bedroom")
        #expect(ValueExtractor.timeout == .seconds(2))
        #expect(ValueExtractor(client: GeminiClient(apiKey: "k")).timeout == ValueExtractor.timeout)
    }

    @Test func theReaderSeesTheScreensSelectionAndVisibleTextBeforeTheRequest() {
        let screen = Screen(kind: .page, title: "Dyson PencilVac | Dyson", address: URL(string: "https://www.dyson.com/pencilvac"), visible: "Dyson PencilVac\n$449.99", rest: "Specifications", items: [ScreenItem(title: "Basket", address: URL(string: "https://www.dyson.com/basket")!)])
        let input = ValueExtractor.input(query: "how much is this", exchanges: [], screen: screen)
        #expect(input == "\nOn screen: the page \"Dyson PencilVac | Dyson\" at https://www.dyson.com/pencilvac\nVisible:\nDyson PencilVac\n$449.99\n\nRequest: how much is this")
        #expect(!input.contains("Specifications") && !input.contains("Basket"), "the reader gets what is in view, not the rest or the links")
        #expect(QueryReader.system.contains(Screen.rule))
        #expect(QueryReader.request(query: "q", screen: screen).input.contains("On screen"))
        let answer = AnswerPrompt.input(query: "how much is this", context: .example, persona: .example, screen: screen)
        #expect(answer.contains("What Lorcan sees on screen as they ask (\(Screen.rule)):\nOn screen: the page \"Dyson PencilVac | Dyson\" at https://www.dyson.com/pencilvac\nVisible now:\nDyson PencilVac\n$449.99\nFurther down the page:\nSpecifications\nLinks in view, in order:\n- 1: \"Basket\""), "an answer gets the whole screen, the links numbered")
        #expect(!AnswerPrompt.input(query: "q", context: .example, screen: Screen(kind: .page, title: "t")).contains("sees on screen"), "a screen with nothing but a title adds nothing")
    }
}
