import Foundation
import Testing
@testable import Engine

@Suite struct RequestShapeTests {
    private let locale = Locale(identifier: "en_US")

    @Test func requestMatchesDocumentedShape() throws {
        let request = EngineRequest.request(for: "nasdaq stock", locale: locale, model: "jev-1.13.0")
        let data = try request.jsonData()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["model"] as? String == "jev-1.13.0")
        let state = try #require(json["state"] as? [String: Any])
        #expect(state["query"] as? String == "nasdaq stock")
        #expect(state["locale"] as? String == "en_US")

        let questions = try #require(json["questions"] as? [String: Any])
        let format = try #require(questions["instinct"] as? [String: Any])
        #expect(format["type"] as? String == "choice")
        #expect((format["instructions"] as? String)?.isEmpty == false)

        let criteria = try #require(format["criteria"] as? [String: Any])
        #expect(Set(criteria.keys) == Set(Instinct.allCases.map(\.rawValue)))
        #expect(Set(criteria.keys) == Set(InstinctSpec.all.map(\.id)), "the options are the registry")
        let stock = try #require(criteria["stock"] as? [String: Any])
        #expect(stock["what"] is String)
        #expect(stock["not_for"] is String)
        #expect((stock["examples"] as? [String])?.isEmpty == false)
    }

    @Test func recencyQuestionIsANoulAfterTheFormatChoice() throws {
        let request = EngineRequest.request(for: "is charlie kirk alive", locale: locale)
        let data = try request.jsonData()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let questions = try #require(json["questions"] as? [String: Any])
        let recent = try #require(questions["recent"] as? [String: Any])
        #expect(recent["type"] as? String == "noul")
        #expect((recent["instructions"] as? String)?.contains("changed in the last two years") == true)
        let criteria = try #require(recent["criteria"] as? [String: String])
        #expect(Set(criteria.keys) == ["true", "false"])

        let text = String(decoding: data, as: UTF8.self)
        let pickAt = try #require(text.range(of: "\"instinct\":")).lowerBound
        let recentAt = try #require(text.range(of: "\"recent\":")).lowerBound
        #expect(pickAt < recentAt, "the pick stays first")
    }

    @Test func withoutExchangesTheStateIsBareAndNoRelevanceIsAsked() throws {
        let request = EngineRequest.request(for: "capital of peru", locale: locale)
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        #expect(Set(state.keys) == ["query", "locale"])
        let questions = try #require(json["questions"] as? [String: Any])
        #expect(questions["x0"] == nil)
        #expect(questions["continues"] == nil, "the chain replaced the continues question")
        #expect((questions["instinct"] as? [String: Any])?["instructions"] as? String == EngineRequest.instructions)
        #expect(request.questions.map(\.id) == ["instinct", "recent"] + EngineRequest.recallQuestionIDs + ["remember", "notebook.action?", "notebook.action", "notebook.all?", "notebook.all", "reasoning"])
    }

    @Test func exchangesAddStateReadTheQueryInContextAndAskRelevancePerExchange() throws {
        let exchanges = answerExchanges([
            (query: "how do you make chocolate milk", answer: "Stir **cocoa and sugar** into cold milk."),
            (query: "why cold?", answer: "Cocoa clumps in hot milk."),
        ])
        let request = EngineRequest.request(for: "can I use water", locale: locale, exchanges: exchanges)
        let data = try request.jsonData()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        let sent = try #require(state["exchanges"] as? [[String: Any]])
        #expect(sent.count == 2)
        #expect(sent[0]["query"] as? String == "how do you make chocolate milk")
        #expect(sent[0]["kind"] as? String == "answer")
        #expect(sent[0]["text"] as? String == "Stir **cocoa and sugar** into cold milk.", "the answer whole, markup included")
        #expect(Set(sent[0].keys) == ["query", "kind", "text"], "nil fields stay off the wire")
        #expect(sent[1]["query"] as? String == "why cold?")
        #expect(state["conversation"] == nil)
        let questions = try #require(json["questions"] as? [String: Any])
        let format = try #require(questions["instinct"] as? [String: Any])
        #expect(format["instructions"] as? String == EngineRequest.contextInstructions())
        for (index, exchange) in exchanges.enumerated() {
            let question = try #require(questions["x\(index)"] as? [String: Any], "x\(index)")
            #expect(question["type"] as? String == "noul")
            #expect((question["instructions"] as? String)?.contains("\"\(exchange.query)\"") == true, "the question names its exchange")
            #expect((question["instructions"] as? String)?.contains("exchange \(index + 1) of 2") == true)
            let criteria = try #require(question["criteria"] as? [String: String])
            #expect(Set(criteria.keys) == ["true", "false"])
            #expect(criteria["true"]?.contains("wait no I meant brazil") == true)
        }
        #expect(request.questions.map(\.id) == ["instinct", "recent"] + EngineRequest.recallQuestionIDs + ["remember", "notebook.action?", "notebook.action", "notebook.all?", "notebook.all", "x0", "x1", "reasoning"], "the format choice stays first, the score last")
    }

    @Test func aPageExchangeCarriesItsTitleHostAndAddress() throws {
        let exchanges = [Exchange.page(query: "brasil weather", title: "Weather in Brasília", address: URL(string: "https://weather.com/br/brasilia")!)]
        let request = EngineRequest.request(for: "how big is it", locale: locale, exchanges: exchanges)
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let sent = try #require((json["state"] as? [String: Any])?["exchanges"] as? [[String: Any]])
        #expect(sent[0]["kind"] as? String == "page")
        #expect(sent[0]["title"] as? String == "Weather in Brasília")
        #expect(sent[0]["host"] as? String == "weather.com")
        #expect(sent[0]["address"] as? String == "https://weather.com/br/brasilia")
        #expect(sent[0]["text"] == nil)
        let question = try #require((json["questions"] as? [String: Any])?["x0"] as? [String: Any])
        #expect((question["instructions"] as? String)?.contains("the page \"Weather in Brasília\" on weather.com") == true)
    }

    @Test func aTurnDecodesAsNarrativeWithoutAFormatAndKeepsOneLine() throws {
        let old = #"{"query":"capital of peru","answer":"Lima"}"#
        let decoded = try JSONDecoder().decode(AnswerTurn.self, from: Data(old.utf8))
        #expect(decoded == AnswerTurn(query: "capital of peru", answer: "Lima", format: .narrative))
        let turn = AnswerTurn(query: "and chile?", answer: "==Santiago==", format: .oneLine)
        #expect(try JSONDecoder().decode(AnswerTurn.self, from: JSONEncoder().encode(turn)) == turn)
        #expect(String(decoding: try JSONEncoder().encode(turn), as: UTF8.self).contains("\"one_line\""))
    }

    @Test func theContextInstructionsNameEveryCardFormat() {
        let text = EngineRequest.contextInstructions()
        #expect(text.contains("one_line when the reply is itself a single short fact"))
        for format in Instinct.allCases where format.outranksConversation {
            #expect(text.contains(format.rawValue), "\(format.rawValue) is missing from the context instructions")
        }
        #expect(text.contains("as the exchanges it depends on make it"))
        #expect(text.contains("wait no I meant brazil"), "a correction of a search is named")
        #expect(!EngineRequest.instructions.contains("exchanges"), "the standalone question is unchanged")
    }

    @Test func aLongSessionSendsTheNewestTwentyWhole() {
        let long = String(repeating: "x", count: 20_000)
        let exchanges = (0..<30).map { Exchange.answer(query: "q\($0)", text: $0 == 29 ? long : "a\($0)") }
        let request = EngineRequest.request(for: "why", locale: locale, exchanges: exchanges)
        let sent = request.state.exchanges ?? []
        #expect(sent.count == EngineRequest.maxExchanges)
        #expect(sent.first?.query == "q10" && sent.last?.query == "q29", "the newest, oldest first")
        #expect(sent.last?.text == long, "no answer is cut")
        #expect(request.questions.filter { $0.id.hasPrefix("x") }.count == EngineRequest.maxExchanges)
    }

    @Test func theReasoningQuestionIsAScoreWithThreeLevels() throws {
        let request = EngineRequest.request(for: "set the thermostat to 68", locale: locale)
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let reasoning = try #require((json["questions"] as? [String: Any])?["reasoning"] as? [String: Any])
        #expect(reasoning["type"] as? String == "score")
        #expect((reasoning["instructions"] as? String)?.contains("How much working out") == true)
        let levels = try #require(reasoning["criteria"] as? [String])
        #expect(levels.count == 3)
        #expect(levels == EngineRequest.reasoningLevels, "low to high, in order")
        #expect(levels[0].hasPrefix("Direct"))
        #expect(levels[1].contains("68"))
        #expect(levels[2].contains("Several steps"))
        #expect(request.questions.last?.id == "reasoning")
    }

    @Test func anInstinctsClosedSetFieldsAreTwoQuestionsEachReadForThePickOnly() throws {
        let thermostat = InstinctSpec(instinct: .stock, arguments: ArgumentSchema(fields: [
            .init(name: "mode", kind: .choice(["heat", "cool"]), description: "heat or cool"),
            .init(name: "fan", kind: .boolean, description: "the fan on", required: false),
            .init(name: "temperature", kind: .integer, description: "the degrees"),
        ]))
        let instincts = InstinctSpec.all.map { $0.instinct == .stock ? thermostat : $0 }
        let request = EngineRequest.request(for: "cool it to 68 with the fan", locale: locale, instincts: instincts)
        let ids = request.questions.map(\.id)
        #expect(ids.contains("stock.mode?") && ids.contains("stock.mode") && ids.contains("stock.fan?") && ids.contains("stock.fan"))
        #expect(!ids.contains("stock.temperature?") && !ids.contains("stock.temperature"), "a free-form field is a model's to read, not Jev's")
        #expect(ids.last == "reasoning")
        #expect(ids.firstIndex(of: "stock.mode?")! > ids.firstIndex(of: "recall_all")!, "after the instincts' own questions")
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let questions = try #require(json["questions"] as? [String: Any])
        let mode = try #require(questions["stock.mode"] as? [String: Any])
        #expect(mode["type"] as? String == "choice")
        #expect(Set((mode["criteria"] as? [String: Any])?.keys.map { $0 } ?? []) == ["heat", "cool"])
        #expect((mode["instructions"] as? String)?.contains("heat or cool") == true)
        #expect((questions["stock.mode?"] as? [String: Any])?["type"] as? String == "noul")
        #expect((questions["stock.fan"] as? [String: Any])?["type"] as? String == "noul")

        func decide(_ json: String) throws -> Pick {
            EngineRequest.decision(from: try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8)), latencyMs: 1, instincts: instincts)
        }
        let stated = try decide(jevResponse(choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9], nouls: ["stock.mode?": 0.9, "stock.fan?": 0.8, "stock.fan": 0.95], choices: ["stock.mode": (choice: "cool", confidence: 0.8)]))
        #expect(stated.arguments == ["mode": "cool", "fan": "true"])
        let unstated = try decide(jevResponse(choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9], nouls: ["stock.mode?": 0.2, "stock.fan?": 0.1, "stock.fan": 0.95], choices: ["stock.mode": (choice: "cool", confidence: 0.8)]))
        #expect(unstated.arguments == nil, "a value the words did not state is left to the default")
        let unsure = try decide(jevResponse(choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9], nouls: ["stock.mode?": 0.9, "stock.fan?": 0.9, "stock.fan": 0.2], choices: ["stock.mode": (choice: "cool", confidence: 0.3)]))
        #expect(unsure.arguments == ["fan": "false"], "an unsure choice is dropped; a stated no is a no")
        let otherPick = try decide(jevResponse(choice: "web_results", confidence: 0.9, probabilities: ["web_results": 0.9], nouls: ["stock.mode?": 0.9, "stock.fan?": 0.8, "stock.fan": 0.95], choices: ["stock.mode": (choice: "cool", confidence: 0.8)]))
        #expect(otherPick.arguments == nil, "read for the pick only")
        #expect(try JSONDecoder().decode(Pick.self, from: JSONEncoder().encode(stated)).arguments == ["mode": "cool", "fan": "true"])
        #expect(EngineRequest.request(for: "x", locale: locale).questions.map(\.id) == ["instinct", "recent"] + EngineRequest.recallQuestionIDs + ["remember", "notebook.action?", "notebook.action", "notebook.all?", "notebook.all", "reasoning"], "no instinct declares a closed-set field today")
    }

    @Test func scoreAnswerDecodes() throws {
        let json = """
        { "model": "jev-1.13.0", "answers": { "reasoning": { "type": "score", "score": 1.62, "confidence": 0.71, "probabilities": { "0": 0.08, "1": 0.22, "2": 0.7 }, "legend": { "0": "Direct", "1": "A value", "2": "Several steps" } } }, "usage": { "input_tokens": 1, "output_tokens": 0 } }
        """
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8))
        guard case let .score(answer)? = response.answers["reasoning"] else {
            Issue.record("expected a score answer")
            return
        }
        #expect(answer.score == 1.62)
        #expect(answer.confidence == 0.71)
        #expect(answer.probability(ofLevel: 2) == 0.7)
        #expect(answer.probability(ofLevel: 3) == 0)
        #expect(Question.score(instructions: "a", levels: ["x", "y"]) == Question.score(instructions: "a", levels: ["x", "y"]))
        #expect(Question.score(instructions: "a", levels: ["x", "y"]) != Question.score(instructions: "a", levels: ["x"]))
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
        let request = EngineRequest.request(for: "anything", locale: locale)
        let text = String(decoding: try request.jsonData(), as: UTF8.self)
        let criteriaStart = try #require(text.range(of: "\"criteria\"")).upperBound
        let tail = text[criteriaStart...]

        let positions = InstinctSpec.all.map { spec in
            tail.range(of: "\"\(spec.id)\":")!.lowerBound
        }
        #expect(positions == positions.sorted(), "options must reach Jev in registry order")
        #expect(InstinctSpec.all.first?.instinct == .webResults, "the safe fallback goes first; Jev leans toward the first option")
        #expect(InstinctSpec.all.map(\.instinct) == Instinct.allCases, "the registry is the format list, in order")
    }

    @Test func everyFormatHasUsableCriteria() {
        for format in Instinct.allCases {
            let criterion = format.criterion
            #expect(!criterion.what.isEmpty, "\(format) needs a description")
            #expect(!criterion.notFor.isEmpty, "\(format) needs a boundary")
            #expect(criterion.examples.count >= 3, "\(format) needs examples")
            #expect(format.rawValue == format.rawValue.lowercased())
            #expect(!format.rawValue.contains(" "))
        }
        #expect(Instinct.fallback == .webResults)
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
        let request = EngineRequest.request(for: "no not this one", locale: Locale(identifier: "en_US"), opened: OpenedSite(name: "zillow", host: "www.zillow.com"))
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
        #expect(questions["x0"] == nil, "no exchanges, no relevance questions")
        #expect((questions["instinct"] as? [String: Any])?["instructions"] as? String == EngineRequest.instructions, "the format question reads the query as typed")
        #expect(request.questions.map(\.id) == ["instinct", "recent"] + EngineRequest.recallQuestionIDs + ["rejects", "remember", "notebook.action?", "notebook.action", "notebook.all?", "notebook.all", "reasoning"], "the format choice stays first")
    }

    @Test func anOpenedSiteAndExchangesCoexist() throws {
        let page = Exchange.page(query: "pull up zillow", title: "Zillow", address: URL(string: "https://www.zillow.com/")!)
        let request = EngineRequest.request(for: "no not this one", locale: Locale(identifier: "en_US"), exchanges: [page], opened: OpenedSite(name: "zillow", host: "www.zillow.com"))
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        #expect(Set(state.keys) == ["query", "locale", "exchanges", "opened_site_name", "opened_site_host"])
        #expect(request.questions.map(\.id) == ["instinct", "recent"] + EngineRequest.recallQuestionIDs + ["rejects", "remember", "notebook.action?", "notebook.action", "notebook.all?", "notebook.all", "x0", "reasoning"])
    }

    @Test func withoutAnOpenedSiteNothingIsAdded() throws {
        let request = EngineRequest.request(for: "go to youtube", locale: Locale(identifier: "en_US"))
        let json = try #require(JSONSerialization.jsonObject(with: try request.jsonData()) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        #expect(Set(state.keys) == ["query", "locale"])
        #expect(request.questions.map(\.id) == ["instinct", "recent"] + EngineRequest.recallQuestionIDs + ["remember", "notebook.action?", "notebook.action", "notebook.all?", "notebook.all", "reasoning"])
        let criteria = try #require(((json["questions"] as? [String: Any])?["instinct"] as? [String: Any])?["criteria"] as? [String: Any])
        #expect(criteria["site"] != nil, "site is one of the options")
        #expect(Array(Instinct.allCases.map(\.rawValue)).suffix(6) == ["site", "video", "remember", "forget", "time", "notebook"], "appended in order, so the other options keep theirs")
    }
}
