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

    @Test func withoutAPreviousTurnTheRequestIsUnchanged() throws {
        let request = JevRouting.request(for: "capital of peru", locale: Locale(identifier: "en_US"))
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        #expect(Set(state.keys) == ["query", "locale"])
        let questions = try #require(json["questions"] as? [String: Any])
        #expect(questions["continues"] == nil)
        #expect((questions["format"] as? [String: Any])?["instructions"] as? String == JevRouting.instructions)
        #expect(request.questions.map(\.id) == ["format", "recent"] + JevRouting.recallQuestionIDs)
    }

    @Test func aThreadAddsStateReadsTheQueryInContextAndAsksIfItContinues() throws {
        let thread = [
            AnswerTurn(query: "how do you make chocolate milk", answer: "Stir **cocoa and sugar** into cold milk."),
            AnswerTurn(query: "why cold?", answer: "Cocoa clumps in hot milk."),
        ]
        let request = JevRouting.request(for: "can I use water", locale: Locale(identifier: "en_US"), thread: thread)
        let data = try request.jsonData()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        let conversation = try #require(state["conversation"] as? [[String: String]])
        #expect(conversation == [
            ["query": "how do you make chocolate milk", "answer": "Stir **cocoa and sugar** into cold milk."],
            ["query": "why cold?", "answer": "Cocoa clumps in hot milk."],
        ], "every query and every answer, oldest first, without the format")
        #expect(state["previous_queries"] == nil && state["previous_answer"] == nil)
        let questions = try #require(json["questions"] as? [String: Any])
        let format = try #require(questions["format"] as? [String: Any])
        #expect(format["instructions"] as? String == JevRouting.followUpInstructions)
        let continues = try #require(questions["continues"] as? [String: Any])
        #expect(continues["type"] as? String == "noul")
        let criteria = try #require(continues["criteria"] as? [String: String])
        #expect(Set(criteria.keys) == ["true", "false"])
        #expect(criteria["true"]?.contains("can I use water") == true)
        #expect(request.questions.map(\.id) == ["format", "recent"] + JevRouting.recallQuestionIDs + ["continues"], "the format choice stays first")
    }

    @Test func aTurnDecodesAsNarrativeWithoutAFormatAndKeepsOneLine() throws {
        let old = #"{"query":"capital of peru","answer":"Lima"}"#
        let decoded = try JSONDecoder().decode(AnswerTurn.self, from: Data(old.utf8))
        #expect(decoded == AnswerTurn(query: "capital of peru", answer: "Lima", format: .narrative))
        let turn = AnswerTurn(query: "and chile?", answer: "==Santiago==", format: .oneLine)
        #expect(try JSONDecoder().decode(AnswerTurn.self, from: JSONEncoder().encode(turn)) == turn)
        #expect(String(decoding: try JSONEncoder().encode(turn), as: UTF8.self).contains("\"one_line\""))
    }

    @Test func theFollowUpInstructionsNameEveryCardFormat() {
        let text = JevRouting.followUpInstructions
        #expect(text.contains("one_line when the reply is itself a single short fact"))
        for format in ResponseFormat.allCases where format.outranksConversation {
            #expect(text.contains(format.rawValue), "\(format.rawValue) is missing from the follow-up instructions")
        }
        #expect(text.contains("as that conversation makes it"))
        #expect(!JevRouting.instructions.contains("conversation"), "the standalone question is unchanged")
    }

    @Test func aLongConversationGoesWhole() {
        let long = String(repeating: "x", count: 20_000)
        let thread = (0..<30).map { AnswerTurn(query: "q\($0)", answer: $0 == 0 ? long : "a\($0)") }
        let request = JevRouting.request(for: "why", locale: Locale(identifier: "en_US"), thread: thread)
        #expect(request.state.conversation?.count == 30)
        #expect(request.state.conversation?.first?.answer == long, "no answer is cut, the first included")
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

@Suite struct SiteRequestShapeTests {
    @Test func anOpenedSiteAddsStateAndAsksIfTheQueryRejectsIt() throws {
        let request = JevRouting.request(for: "no not this one", locale: Locale(identifier: "en_US"), opened: OpenedSite(name: "zillow", host: "www.zillow.com"))
        let data = try request.jsonData()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        #expect(Set(state.keys) == ["query", "locale", "opened_site_name", "opened_site_host"])
        #expect(state["opened_site_name"] as? String == "zillow")
        #expect(state["opened_site_host"] as? String == "www.zillow.com")
        let questions = try #require(json["questions"] as? [String: Any])
        let rejects = try #require(questions["rejects"] as? [String: Any])
        #expect(rejects["type"] as? String == "noul")
        #expect((rejects["instructions"] as? String)?.contains("opened_site_host") == true)
        let criteria = try #require(rejects["criteria"] as? [String: String])
        #expect(Set(criteria.keys) == ["true", "false"])
        #expect(criteria["true"]?.contains("not this zillow") == true)
        #expect(criteria["false"]?.contains("open youtube") == true)
        #expect(questions["continues"] == nil, "a page on screen means no narrative is")
        #expect((questions["format"] as? [String: Any])?["instructions"] as? String == JevRouting.instructions, "the format question reads the query as typed")
        #expect(request.questions.map(\.id) == ["format", "recent"] + JevRouting.recallQuestionIDs + ["rejects"], "the format choice stays first")
    }

    @Test func withoutAnOpenedSiteNothingIsAdded() throws {
        let request = JevRouting.request(for: "go to youtube", locale: Locale(identifier: "en_US"))
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        #expect(Set(state.keys) == ["query", "locale"])
        #expect(request.questions.map(\.id) == ["format", "recent"] + JevRouting.recallQuestionIDs)
        let criteria = try #require(((json["questions"] as? [String: Any])?["format"] as? [String: Any])?["criteria"] as? [String: Any])
        #expect(criteria["site"] != nil, "site is one of the options")
        #expect(Array(ResponseFormat.allCases.map(\.rawValue)).suffix(2) == ["site", "video"], "appended in order, so the other options keep theirs")
    }
}
