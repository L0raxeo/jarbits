import Foundation
import Routing
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
        #expect(ValueExtractor.timeout == .seconds(1))
        #expect(ValueExtractor(client: GeminiClient(apiKey: "k")).timeout == ValueExtractor.timeout)
    }
}
