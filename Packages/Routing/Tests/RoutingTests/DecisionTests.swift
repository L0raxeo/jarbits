import Foundation
import Testing
@testable import Routing

@Suite struct DecisionTests {
    private func response(choice: String, confidence: Double, probabilities: [String: Double]) throws -> SystemOneResponse {
        try JSONDecoder().decode(
            SystemOneResponse.self,
            from: Data(jevResponse(choice: choice, confidence: confidence, probabilities: probabilities).utf8)
        )
    }

    private func decode(_ json: String) throws -> SystemOneResponse {
        try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8))
    }

    /// The decision over `exchanges`, with the relevance answers lined up to them.
    private func decide(_ json: String, exchanges: [Exchange] = []) throws -> RouteDecision {
        EngineRouting.decision(from: try decode(json), latencyMs: 1, exchanges: exchanges)
    }

    private let recipe = answerExchanges([(query: "how do you make hot chocolate", answer: "Heat milk, whisk in cocoa.")])
    private let search = [Exchange.search(query: "brasil weather", term: "brasil weather")]

    @Test func confidentAnswerPassesTheGate() throws {
        let response = try response(choice: "stock", confidence: 0.91, probabilities: ["stock": 0.92, "web_results": 0.05, "narrative": 0.03])
        let decision = EngineRouting.decision(from: response, latencyMs: 212)
        #expect(decision.format == .stock)
        #expect(decision.suggested == .stock)
        #expect(decision.source == .jev)
        #expect(decision.confidence == 0.91)
        #expect(decision.latencyMs == 212)
        #expect(decision.inputTokens == 512)
        #expect(decision.model == "jev-1.13.0")
        #expect(decision.runnerUp?.format == .webResults)
        #expect(decision.relevance == nil && decision.chain == nil, "no exchanges were sent")
    }

    @Test func recallPassesTheGateLikeAnyFormat() throws {
        let sure = try response(choice: "recall", confidence: 0.88, probabilities: ["recall": 0.88, "web_results": 0.1, "narrative": 0.02])
        #expect(EngineRouting.decision(from: sure, latencyMs: 1).format == .recall)
        let unsure = try response(choice: "recall", confidence: 0.45, probabilities: ["recall": 0.45, "web_results": 0.4, "narrative": 0.15])
        let decision = EngineRouting.decision(from: unsure, latencyMs: 1)
        #expect(decision.format == .webResults)
        #expect(decision.suggested == .recall)
        #expect(decision.source == .confidenceFallback)
    }

    @Test func unsureAnswerFallsBackToWeb() throws {
        let response = try response(choice: "map", confidence: 0.4, probabilities: ["map": 0.46, "web_results": 0.3, "narrative": 0.24])
        let decision = EngineRouting.decision(from: response, latencyMs: 180)
        #expect(decision.format == .webResults)
        #expect(decision.suggested == .map)
        #expect(decision.source == .confidenceFallback)
    }

    /// "can I use mr clean with clorox": torn between a short and a long
    /// answer, never really considering a page.
    @Test func anUnsurePickBetweenTheTwoAnswersIsStillAnAnswer() throws {
        let split = try response(choice: "one_line", confidence: 0.44, probabilities: ["one_line": 0.5, "narrative": 0.29, "web_results": 0.21])
        let decision = EngineRouting.decision(from: split, latencyMs: 1)
        #expect(decision.format == .oneLine)
        #expect(decision.source == .answerSplit)
        let leanLong = try response(choice: "narrative", confidence: 0.38, probabilities: ["narrative": 0.45, "one_line": 0.44, "web_results": 0.11])
        #expect(EngineRouting.decision(from: leanLong, latencyMs: 1).format == .narrative)
    }

    @Test func anAnswerSplitStillNeedsTheMassAndYieldsToRecency() throws {
        let thin = try response(choice: "one_line", confidence: 0.3, probabilities: ["one_line": 0.35, "narrative": 0.2, "web_results": 0.3, "image": 0.15])
        #expect(EngineRouting.decision(from: thin, latencyMs: 1).source == .confidenceFallback, "an answer and a page were both in play")
        let notAnAnswer = try response(choice: "map", confidence: 0.3, probabilities: ["map": 0.36, "narrative": 0.32, "one_line": 0.32])
        #expect(EngineRouting.decision(from: notAnAnswer, latencyMs: 1).source == .confidenceFallback, "only an answered pick is rescued")
        let stale = try decide(jevResponse(choice: "one_line", confidence: 0.4, probabilities: ["one_line": 0.5, "narrative": 0.4, "web_results": 0.1], recency: 0.9))
        #expect(stale.source == .recencyFallback)
    }

    @Test func recentAnswerFormatIsSentToWeb() throws {
        let decision = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.92, "web_results": 0.08], recency: 0.8))
        #expect(decision.format == .webResults)
        #expect(decision.suggested == .narrative)
        #expect(decision.recency == 0.8)
        #expect(decision.source == .recencyFallback)
    }

    @Test func settledAnswerFormatPasses() throws {
        let decision = try decide(jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.92], recency: 0.2))
        #expect(decision.format == .oneLine)
        #expect(decision.source == .jev)
        #expect(decision.recency == 0.2)
    }

    @Test func recencyThresholdIsInclusive() throws {
        let decision = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: EngineRouting.recencyThreshold))
        #expect(decision.source == .recencyFallback)
    }

    @Test func missingRecencyNeverGates() throws {
        let response = try response(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9])
        let decision = EngineRouting.decision(from: response, latencyMs: 1)
        #expect(decision.source == .jev)
        #expect(decision.recency == nil)
    }

    @Test func pageFormatsIgnoreRecency() throws {
        let decision = try decide(jevResponse(choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9], recency: 0.99))
        #expect(decision.format == .stock)
        #expect(decision.source == .jev)
    }

    @Test func unsureBeatsRecency() throws {
        #expect(try decide(jevResponse(choice: "narrative", confidence: 0.3, probabilities: ["narrative": 0.4], recency: 0.9)).source == .confidenceFallback)
    }

    @Test func floorIsInclusive() throws {
        let response = try response(choice: "narrative", confidence: 0.5, probabilities: ["narrative": 0.55, "web_results": 0.45])
        #expect(EngineRouting.decision(from: response, latencyMs: 1).source == .jev)
    }

    @Test func unknownOptionFallsBackToWeb() throws {
        let response = try response(choice: "podcasts", confidence: 0.9, probabilities: ["podcasts": 0.9])
        let decision = EngineRouting.decision(from: response, latencyMs: 1)
        #expect(decision.format == .webResults)
        #expect(decision.suggested == nil)
        if case .error = decision.source {} else { Issue.record("expected an error source") }
    }

    @Test func missingQuestionFallsBackToWebAndStillLogsTheRest() throws {
        let json = """
        { "model": "jev-1.13.0", "answers": { "x0": { "type": "noul", "noul": 0.9 }, "reasoning": { "type": "score", "score": 1.8, "confidence": 0.7, "probabilities": { "2": 0.8 } } }, "usage": { "input_tokens": 1, "output_tokens": 0 } }
        """
        let decision = try decide(json, exchanges: recipe)
        #expect(decision.format == .webResults)
        if case .error = decision.source {} else { Issue.record("expected an error source") }
        #expect(decision.relevance == [0.9] && decision.chain == 1 && decision.reasoning == 1.8, "what did come back is kept for the log")
    }

    // MARK: The chain

    @Test func aChainEndingOnAnAnswerGrowsIt() throws {
        let decision = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1, relevance: [0.8]), exchanges: recipe)
        #expect(decision.relevance == [0.8])
        #expect(decision.chain == 1)
        #expect(decision.format == .narrative)
        #expect(decision.source == .continuation)
        #expect(decision.continuesThread)
        #expect(decision.continuation == nil, "the old field is never written now")
    }

    @Test func aTerseReplyThreadsWhateverItLookedLikeOnItsOwn() throws {
        // "can I use water": flat and web first, a confident web pick, an unsure one-liner, an unsure picture.
        for (choice, confidence) in [("web_results", 0.3), ("web_results", 0.9), ("narrative", 0.2), ("one_line", 0.4), ("image", 0.3)] {
            let decision = try decide(jevResponse(choice: choice, confidence: confidence, probabilities: [choice: 0.5], relevance: [0.9]), exchanges: recipe)
            #expect(decision.format == .narrative, "\(choice) at \(confidence)")
            #expect(decision.source == .continuation, "\(choice) at \(confidence)")
            #expect(decision.suggested == ResponseFormat(rawValue: choice), "the pick is kept for the log")
        }
    }

    @Test func aConfidentOneLinePickIsAShortTurnOfTheThread() throws {
        // "and chile?" after "capital of peru": a one-line reply inside the conversation.
        let capital = answerExchanges([(query: "capital of peru", answer: "==Lima==")])
        let decision = try decide(jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.92, "narrative": 0.05], recency: 0.1, relevance: [0.9]), exchanges: capital)
        #expect(decision.format == .oneLine)
        #expect(decision.source == .continuation)
        #expect(decision.continuesThread)
        let stale = try decide(jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.92], recency: 0.9, relevance: [0.9]), exchanges: capital)
        #expect(stale.source == .recencyFallback, "a short reply that needs live data still goes to web")
    }

    @Test func aRelatedAskForAnotherCardGetsThatCard() throws {
        // "pictures of chocolate milk" after the recipe: related, and a picture.
        for format in ResponseFormat.allCases where format.outranksConversation {
            let decision = try decide(jevResponse(choice: format.rawValue, confidence: 0.9, probabilities: [format.rawValue: 0.9], relevance: [0.9]), exchanges: recipe)
            #expect(decision.format == format, "\(format)")
            #expect(decision.source == .jev, "\(format)")
            #expect(decision.chain == 1, "the chain is still logged")
            #expect(!decision.continuesThread)
        }
    }

    @Test func aStaleContinuationStillGoesToWeb() throws {
        let decision = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.9, relevance: [0.95]), exchanges: recipe)
        #expect(decision.format == .webResults)
        #expect(decision.source == .recencyFallback)
        #expect(!decision.continuesThread)
    }

    @Test func theChainStopsAtTheFirstNoAndLogsEveryAnswer() throws {
        let three = answerExchanges([(query: "q1", answer: "a1"), (query: "q2", answer: "a2"), (query: "q3", answer: "a3")])
        let decision = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], relevance: [1, 0, 1]), exchanges: three)
        #expect(decision.relevance == [1, 0, 1], "oldest first, the yes behind the no kept")
        #expect(decision.chain == 1)
        #expect(decision.continuesThread)
        #expect(EngineRouting.chain([1, 1, 1]) == 3)
        #expect(EngineRouting.chain([1, 1, 0]) == 0)
        #expect(EngineRouting.chain([]) == 0)
        #expect(EngineRouting.chain([0.5]) == 1, "the threshold is inclusive")
        #expect(EngineRouting.chain([0.49]) == 0)
    }

    @Test func aChainEndingOnAPageKeepsThePickAndCountsTheChain() throws {
        // "wait no I meant brazil" after a search: web results, read with the correction.
        let web = try decide(jevResponse(choice: "web_results", confidence: 0.8, probabilities: ["web_results": 0.85], relevance: [0.9]), exchanges: search)
        #expect(web.format == .webResults)
        #expect(web.source == .jev)
        #expect(web.chain == 1)
        #expect(!web.continuesThread, "a search is not an answer to grow")
        // "how big is it" after reading a page: a narrative with the page as context.
        let page = [Exchange.page(query: "brasil weather", title: "Weather in Brasília", address: URL(string: "https://weather.com/br")!)]
        let narrative = try decide(jevResponse(choice: "narrative", confidence: 0.8, probabilities: ["narrative": 0.85], recency: 0.1, relevance: [0.9]), exchanges: page)
        #expect(narrative.format == .narrative)
        #expect(narrative.source == .jev)
        #expect(narrative.chain == 1)
        #expect(!narrative.continuesThread)
        // An unsure pick over a page still falls back to web.
        let unsure = try decide(jevResponse(choice: "narrative", confidence: 0.3, probabilities: ["narrative": 0.4], relevance: [0.9]), exchanges: page)
        #expect(unsure.source == .confidenceFallback)
    }

    @Test func relevanceThresholdIsInclusiveAndAMissingAnswerIsANo() throws {
        let at = try decide(jevResponse(choice: "web_results", confidence: 0.3, probabilities: ["web_results": 0.4], relevance: [EngineRouting.relevanceThreshold]), exchanges: recipe)
        #expect(at.source == .continuation)
        let under = try decide(jevResponse(choice: "web_results", confidence: 0.3, probabilities: ["web_results": 0.4], relevance: [EngineRouting.relevanceThreshold - 0.01]), exchanges: recipe)
        #expect(under.source == .confidenceFallback)
        #expect(under.chain == 0)
        let unanswered = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9]), exchanges: recipe)
        #expect(unanswered.relevance == [0], "exchanges were sent, so the answers are logged, a missing one as a no")
        #expect(unanswered.chain == 0)
        #expect(unanswered.source == .jev, "a fresh narrative, not a thread")
    }

    @Test func belowTheThresholdTheUsualRulesHold() throws {
        let sure = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], relevance: [0.2]), exchanges: recipe)
        #expect(sure.format == .narrative)
        #expect(sure.source == .jev)
        #expect(!sure.continuesThread, "a fresh narrative, not a thread")
        let unsure = try decide(jevResponse(choice: "narrative", confidence: 0.3, probabilities: ["narrative": 0.4], relevance: [0.2]), exchanges: recipe)
        #expect(unsure.source == .confidenceFallback)
        let unasked = try response(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9])
        #expect(EngineRouting.decision(from: unasked, latencyMs: 1).relevance == nil)
        #expect(!EngineRouting.decision(from: unasked, latencyMs: 1).continuesThread)
    }

    // MARK: The reasoning score

    @Test func reasoningIsLoggedAndMarksAnUnsurePickThatLeansToSeveralSteps() throws {
        let direct = try decide(jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.9], recency: 0.1, reasoning: (score: 0.2, confidence: 0.8)))
        #expect(direct.reasoning == 0.2)
        #expect(direct.reasoningConfidence == 0.8)
        #expect(direct.source == .jev, "the score never gates a confident pick")
        #expect(!direct.reasoningWanted)
        let wanted = try decide(jevResponse(choice: "web_results", confidence: 0.3, probabilities: ["web_results": 0.4, "narrative": 0.3], reasoning: (score: 1.7, confidence: 0.6)))
        #expect(wanted.source == .confidenceFallback)
        #expect(wanted.format == .webResults, "stage 1 still shows web results")
        #expect(wanted.reasoningWanted)
        let low = try decide(jevResponse(choice: "web_results", confidence: 0.3, probabilities: ["web_results": 0.4, "narrative": 0.3], reasoning: (score: 0.4, confidence: 0.9)))
        #expect(!low.reasoningWanted)
        let confident = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1, reasoning: (score: 1.9, confidence: 0.9)))
        #expect(confident.source == .jev && !confident.reasoningWanted, "a confident pick runs, whatever the score")
        #expect(try decide(jevResponse(choice: "web_results", confidence: 0.3, probabilities: ["web_results": 0.4], reasoning: (score: EngineRouting.reasoningThreshold, confidence: 0.5))).reasoningWanted, "inclusive")
    }

    @Test func aMissingScoreNeverGates() throws {
        let decision = try decide(jevResponse(choice: "narrative", confidence: 0.3, probabilities: ["narrative": 0.4]))
        #expect(decision.reasoning == nil)
        #expect(decision.reasoningConfidence == nil)
        #expect(!decision.reasoningWanted)
        #expect(decision.source == .confidenceFallback)
    }

    // MARK: The log

    @Test func chainRoundTripsAndOldLinesDecode() throws {
        let decision = RouteDecision(
            format: .narrative, suggested: .webResults, confidence: 0.3, probabilities: ["web_results": 0.4],
            recency: 0.1, relevance: [0.2, 0.8], chain: 1, reasoning: 0.3, reasoningConfidence: 0.7, source: .continuation
        )
        #expect(try JSONDecoder().decode(RouteDecision.self, from: JSONEncoder().encode(decision)) == decision)
        let old = #"{"format":"narrative","probabilities":{},"source":{"jev":{}}}"#
        let decoded = try JSONDecoder().decode(RouteDecision.self, from: Data(old.utf8))
        #expect(decoded.relevance == nil && decoded.chain == nil && decoded.reasoning == nil)
        #expect(!decoded.continuesThread)
        let withContinuation = #"{"format":"narrative","probabilities":{},"continuation":0.8,"source":{"continuation":{}}}"#
        let older = try JSONDecoder().decode(RouteDecision.self, from: Data(withContinuation.utf8))
        #expect(older.continuation == 0.8, "a line from before the chain still reads")
        #expect(older.continuesThread)
    }

    @Test func decisionRoundTripsThroughJSON() throws {
        let decision = RouteDecision(
            format: .webResults, suggested: .oneLine, confidence: 0.3,
            probabilities: ["one_line": 0.37, "web_results": 0.33], model: "jev-1.13.0",
            latencyMs: 150, inputTokens: 500, source: .confidenceFallback
        )
        let data = try JSONEncoder().encode(decision)
        #expect(try JSONDecoder().decode(RouteDecision.self, from: data) == decision)
        let error = RouteDecision(format: .webResults, source: .error("http 401: bad key"))
        #expect(try JSONDecoder().decode(RouteDecision.self, from: JSONEncoder().encode(error)) == error)
    }
}

@Suite struct SiteDecisionTests {
    private func decision(_ json: String, exchanges: [Exchange] = []) throws -> RouteDecision {
        EngineRouting.decision(from: try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8)), latencyMs: 1, exchanges: exchanges)
    }

    @Test func aConfidentSitePickPasses() throws {
        let decision = try decision(jevResponse(choice: "site", confidence: 0.9, probabilities: ["site": 0.91, "web_results": 0.06, "recall": 0.03], recency: 0.1))
        #expect(decision.format == .site)
        #expect(decision.source == .jev)
        #expect(decision.rejection == nil)
        #expect(!decision.rejectsSite)
    }

    @Test func anUnsureSitePickFallsBackLikeAnyFormat() throws {
        let decision = try decision(jevResponse(choice: "site", confidence: 0.4, probabilities: ["site": 0.45, "web_results": 0.4], recency: 0.1))
        #expect(decision.format == .webResults)
        #expect(decision.suggested == .site)
        #expect(decision.source == .confidenceFallback)
    }

    @Test func aRejectionIsASiteRequestWhateverThePick() throws {
        // "no not this one" has no format of its own: Jev is unsure between web and narrative.
        let decision = try decision(jevResponse(choice: "web_results", confidence: 0.1, probabilities: ["web_results": 0.3, "narrative": 0.28, "site": 0.1], recency: 0.2, rejects: 0.92))
        #expect(decision.format == .site)
        #expect(decision.suggested == .webResults)
        #expect(decision.source == .rejection)
        #expect(decision.rejection == 0.92)
        #expect(decision.rejectsSite)
    }

    @Test func aRejectionBeatsTheChain() throws {
        let page = [Exchange.page(query: "pull up zillow", title: "Zillow", address: URL(string: "https://www.zillow.com/")!)]
        let decision = try decision(jevResponse(choice: "web_results", confidence: 0.1, probabilities: ["web_results": 0.3], rejects: 0.9, relevance: [0.95]), exchanges: page)
        #expect(decision.source == .rejection)
        #expect(decision.chain == 1, "still logged")
    }

    @Test func belowTheRejectionThresholdTheOrdinaryRulesApply() throws {
        let fresh = try decision(jevResponse(choice: "site", confidence: 0.9, probabilities: ["site": 0.92, "web_results": 0.08], recency: 0.1, rejects: 0.2))
        #expect(fresh.format == .site)
        #expect(fresh.source == .jev, "\"open youtube\" over zillow is a new site request, not a rejection")
        #expect(fresh.rejection == 0.2)
        let question = try decision(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.92, "web_results": 0.08], recency: 0.1, rejects: 0.05))
        #expect(question.format == .narrative)
        #expect(question.source == .jev)
    }

    @Test func theRejectionThresholdIsInclusive() throws {
        let decision = try decision(jevResponse(choice: "web_results", confidence: 0.2, probabilities: ["web_results": 0.4], rejects: EngineRouting.rejectionThreshold))
        #expect(decision.source == .rejection)
    }
}
