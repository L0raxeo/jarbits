import Foundation
import Testing
@testable import Routing

@Suite struct RequestShapeTests {
    @Test func requestMatchesDocumentedShape() throws {
        let request = JevRouting.request(for: "nasdaq stock", locale: Locale(identifier: "en_US"), model: "jev-1.13.0")
        let data = try request.jsonData()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["model"] as? String == "jev-1.13.0")
        let state = try #require(json["state"] as? [String: Any])
        #expect(state["query"] as? String == "nasdaq stock")
        #expect(state["locale"] as? String == "en_US")

        let questions = try #require(json["questions"] as? [String: Any])
        let format = try #require(questions["format"] as? [String: Any])
        #expect(format["type"] as? String == "choice")
        #expect((format["instructions"] as? String)?.isEmpty == false)

        let criteria = try #require(format["criteria"] as? [String: Any])
        #expect(Set(criteria.keys) == Set(ResponseFormat.allCases.map(\.rawValue)))
        let stock = try #require(criteria["stock"] as? [String: Any])
        #expect(stock["what"] is String)
        #expect(stock["not_for"] is String)
        #expect((stock["examples"] as? [String])?.isEmpty == false)
    }

    @Test func recencyQuestionIsANoulAfterTheFormatChoice() throws {
        let request = JevRouting.request(for: "is charlie kirk alive", locale: Locale(identifier: "en_US"))
        let data = try request.jsonData()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let questions = try #require(json["questions"] as? [String: Any])
        let recent = try #require(questions["recent"] as? [String: Any])
        #expect(recent["type"] as? String == "noul")
        #expect((recent["instructions"] as? String)?.contains("changed in the last two years") == true)
        let criteria = try #require(recent["criteria"] as? [String: String])
        #expect(Set(criteria.keys) == ["true", "false"])

        let text = String(decoding: data, as: UTF8.self)
        let formatAt = try #require(text.range(of: "\"format\":")).lowerBound
        let recentAt = try #require(text.range(of: "\"recent\":")).lowerBound
        #expect(formatAt < recentAt, "the format choice stays first")
    }

    @Test func noulAnswerDecodes() throws {
        let response = try JSONDecoder().decode(
            SystemOneResponse.self,
            from: Data(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.83).utf8)
        )
        #expect(response.answers["recent"] == .noul(0.83))
    }

    @Test func googleResultsPagesAreRecognised() {
        #expect(QueryParser.isSearchResults(QueryParser.searchURL(for: "coffee")))
        #expect(QueryParser.isSearchResults(URL(string: "https://google.com/search?q=x")!))
        #expect(!QueryParser.isSearchResults(URL(string: "https://www.google.com/maps")!))
        #expect(!QueryParser.isSearchResults(URL(string: "https://m.youtube.com/")!))
    }

    @Test func criteriaKeepDeclarationOrderOnTheWire() throws {
        let request = JevRouting.request(for: "anything", locale: Locale(identifier: "en_US"))
        let text = String(decoding: try request.jsonData(), as: UTF8.self)
        let criteriaStart = try #require(text.range(of: "\"criteria\"")).upperBound
        let tail = text[criteriaStart...]

        let positions = ResponseFormat.allCases.map { format in
            tail.range(of: "\"\(format.rawValue)\":")!.lowerBound
        }
        #expect(positions == positions.sorted(), "options must reach Jev in ResponseFormat declaration order")
        #expect(ResponseFormat.allCases.first == .webResults, "the safe fallback goes first; Jev leans toward the first option")
    }

    @Test func everyFormatHasUsableCriteria() {
        for format in ResponseFormat.allCases {
            let criterion = format.criterion
            #expect(!criterion.what.isEmpty, "\(format) needs a description")
            #expect(!criterion.notFor.isEmpty, "\(format) needs a boundary")
            #expect(criterion.examples.count >= 3, "\(format) needs examples")
            #expect(format.rawValue == format.rawValue.lowercased())
            #expect(!format.rawValue.contains(" "))
        }
        #expect(ResponseFormat.fallback == .webResults)
    }

    @Test func documentedExampleResponseDecodes() throws {
        let example = """
        {
          "model": "jev-latest",
          "answers": {
            "sentiment": {
              "type": "choice",
              "choice": "frustrated",
              "confidence": 0.82,
              "probabilities": { "frustrated": 0.82, "neutral": 0.15, "pleased": 0.03 }
            },
            "urgency": { "type": "noul", "noul": 0.99 }
          },
          "usage": { "input_tokens": 110, "output_tokens": 9 }
        }
        """
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(example.utf8))
        #expect(response.model == "jev-latest")
        #expect(response.usage.inputTokens == 110)
        guard case let .choice(answer)? = response.answers["sentiment"] else {
            Issue.record("expected a choice answer")
            return
        }
        #expect(answer.choice == "frustrated")
        #expect(answer.confidence == 0.82)
        #expect(answer.probabilities.count == 3)
        #expect(response.answers["urgency"] == .noul(0.99))
    }
}
