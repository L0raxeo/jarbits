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

    @Test func eachFormatHasItsOwnRulesAndBudget() {
        let narrative = AnswerPrompt.system(for: .narrative)
        let oneLine = AnswerPrompt.system(for: .oneLine)
        #expect(narrative != oneLine)
        #expect(narrative.contains("Open with the most immediate, simple answer"))
        #expect(narrative.contains("There is no target length"))
        #expect(!narrative.contains("two to four"), "no word or paragraph count")
        #expect(ResponseFormat.narrative.criterion.examples.contains("whats isi in ipe"))
        #expect(ResponseFormat.oneLine.criterion.notFor.contains("definitions"))
        #expect(narrative.contains("no access to the web"))
        #expect(narrative.contains("Never say when your knowledge ends"), "no cutoff disclaimer in a narrative")
        #expect(!narrative.contains("may be out of date, then"))
        #expect(oneLine.contains("whether a person is alive"))
        #expect(oneLine.contains("one line only"))
        #expect(oneLine.contains("Never more than twelve words"))
        #expect(oneLine.contains("reply with exactly: \(AnswerPrompt.liveDataMarker)"))
        #expect(AnswerPrompt.maxOutputTokens(for: .narrative) > AnswerPrompt.maxOutputTokens(for: .oneLine))
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
