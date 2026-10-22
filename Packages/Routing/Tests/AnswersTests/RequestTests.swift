import Foundation
import Routing
import Testing
@testable import Answers

@Suite struct RequestTests {
    @Test func bodyMatchesTheDocumentedShape() throws {
        let request = AnswerPrompt.request(format: .oneLine, query: "capital of peru", context: .example)
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])

        #expect(json["model"] as? String == GeminiClient.defaultModel)
        #expect(json["stream"] as? Bool == true)
        #expect(json["store"] as? Bool == false)
        #expect((json["tools"] as? [[String: String]]) == [["type": "google_search"]])
        let generation = try #require(json["generation_config"] as? [String: Any])
        #expect(generation["thinking_level"] as? String == "minimal")
        #expect(generation["max_output_tokens"] as? Int == AnswerPrompt.maxOutputTokens(for: .oneLine))
        #expect(json["system_instruction"] as? String == AnswerPrompt.system(for: .oneLine))
        #expect((json["input"] as? String)?.hasPrefix("Query: capital of peru\n") == true)
    }

    @Test func keyOrderIsStable() throws {
        let body = String(decoding: try AnswerPrompt.request(format: .narrative, query: "q", context: .example).jsonData(), as: UTF8.self)
        let order = ["\"model\"", "\"system_instruction\"", "\"input\"", "\"tools\"", "\"generation_config\"", "\"stream\"", "\"store\""]
        let positions = order.map { body.range(of: $0)!.lowerBound }
        #expect(positions == positions.sorted())
    }

    @Test func eachFormatHasItsOwnRulesAndBudget() {
        let narrative = AnswerPrompt.system(for: .narrative)
        let oneLine = AnswerPrompt.system(for: .oneLine)
        #expect(narrative != oneLine)
        #expect(narrative.contains("Answer only the question that was asked"))
        #expect(narrative.contains("two to four short paragraphs"))
        #expect(oneLine.contains("one line only"))
        #expect(oneLine.contains("Never more than twelve words"))
        #expect(oneLine.contains("Google Search"), "live facts need a search")
        #expect(narrative.contains("Google Search"))
        #expect(AnswerPrompt.maxOutputTokens(for: .narrative) > AnswerPrompt.maxOutputTokens(for: .oneLine))
    }

    @Test func contextCarriesDateZoneLocaleAndLocation() {
        let input = AnswerPrompt.input(query: "will it rain today", context: .example)
        #expect(input.contains("- Date and time: Wednesday 21 October 2026, 11:26 (America/Chicago)"), "got: \(input)")
        #expect(input.contains("- Locale: en_US"))
        #expect(input.contains("- Approximate location: Austin, Texas, United States"))

        var noLocation = AnswerContext.example
        noLocation.location = nil
        #expect(!AnswerPrompt.input(query: "x", context: noLocation).contains("location"))
    }
}
