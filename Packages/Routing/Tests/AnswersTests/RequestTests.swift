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

    @Test func historyIsCappedToTheLastTurns() throws {
        let history = (0..<10).map { AnswerTurn(query: "q\($0)", answer: "a\($0)") }
        let request = AnswerPrompt.request(format: .narrative, query: "q10", context: .example, history: history)
        #expect(request.history.count == AnswerPrompt.maxHistoryTurns)
        #expect(request.history.first?.query == "q\(10 - AnswerPrompt.maxHistoryTurns)")
        let json = try #require(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
        #expect((json["input"] as? [Any])?.count == 2 * AnswerPrompt.maxHistoryTurns + 1)
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
        #expect(ResponseFormat.narrative.criterion.examples.contains("whats isi in ipe"))
        #expect(ResponseFormat.oneLine.criterion.notFor.contains("definitions"))
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
