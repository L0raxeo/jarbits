import Foundation
import Testing
@testable import Engine

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
    private func decide(_ json: String, exchanges: [Exchange] = []) throws -> Pick {
        EngineRequest.decision(from: try decode(json), latencyMs: 1, exchanges: exchanges)
    }

    private let recipe = answerExchanges([(query: "how do you make hot chocolate", answer: "Heat milk, whisk in cocoa.")])
    private let search = [Exchange.search(query: "brasil weather", term: "brasil weather")]

    @Test func confidentAnswerPassesTheGate() throws {
        let response = try response(choice: "stock", confidence: 0.91, probabilities: ["stock": 0.92, "web_results": 0.05, "narrative": 0.03])
        let decision = EngineRequest.decision(from: response, latencyMs: 212)
        #expect(decision.instinct == .stock)
        #expect(decision.suggested == .stock)
        #expect(decision.source == .jev)
        #expect(decision.confidence == 0.91)
        #expect(decision.latencyMs == 212)
        #expect(decision.inputTokens == 512)
        #expect(decision.model == "jev-1.13.0")
        #expect(decision.runnerUp?.instinct == .webResults)
        #expect(decision.relevance == nil && decision.chain == nil, "no exchanges were sent")
    }

    @Test func recallPassesTheGateLikeAnyFormat() throws {
        let sure = try response(choice: "recall", confidence: 0.88, probabilities: ["recall": 0.88, "web_results": 0.1, "narrative": 0.02])
        #expect(EngineRequest.decision(from: sure, latencyMs: 1).instinct == .recall)
        let unsure = try response(choice: "recall", confidence: 0.45, probabilities: ["recall": 0.45, "web_results": 0.4, "narrative": 0.15])
        let decision = EngineRequest.decision(from: unsure, latencyMs: 1)
        #expect(decision.instinct == .webResults)
        #expect(decision.suggested == .recall)
        #expect(decision.source == .confidenceFallback)
    }

    @Test func unsureAnswerFallsBackToWeb() throws {
        let response = try response(choice: "map", confidence: 0.4, probabilities: ["map": 0.46, "web_results": 0.3, "narrative": 0.24])
        let decision = EngineRequest.decision(from: response, latencyMs: 180)
        #expect(decision.instinct == .webResults)
        #expect(decision.suggested == .map)
        #expect(decision.source == .confidenceFallback)
    }

    @Test func anUnsurePickIsWebResultsWhateverItLeanedTo() throws {
        let split = try response(choice: "one_line", confidence: 0.44, probabilities: ["one_line": 0.5, "narrative": 0.29, "web_results": 0.21])
        let decision = EngineRequest.decision(from: split, latencyMs: 1)
        #expect(decision.instinct == .webResults && decision.suggested == .oneLine && decision.source == .confidenceFallback, "no answer-split rescue: the architecture sends an unsure pick to web")
    }

    @Test func recencyIsLoggedOnThePickWhichStands() throws {
        let decision = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.92, "web_results": 0.08], recency: 0.8))
        #expect(decision.instinct == .narrative, "the pick is Jev's; the answer instinct shows web results for a recent one")
        #expect(decision.suggested == .narrative)
        #expect(decision.recency == 0.8)
        #expect(decision.recent)
        #expect(decision.source == .jev)
    }

    @Test func settledAnswerFormatPasses() throws {
        let decision = try decide(jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.92], recency: 0.2))
        #expect(decision.instinct == .oneLine)
        #expect(decision.source == .jev)
        #expect(decision.recency == 0.2)
        #expect(!decision.recent)
    }

    @Test func recencyThresholdIsInclusive() throws {
        let decision = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: EngineRequest.recencyThreshold))
        #expect(decision.recent)
        #expect(decision.source == .jev)
    }

    @Test func missingRecencyIsNotRecent() throws {
        let response = try response(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9])
        let decision = EngineRequest.decision(from: response, latencyMs: 1)
        #expect(decision.source == .jev)
        #expect(decision.recency == nil && !decision.recent)
    }

    @Test func pageFormatsIgnoreRecency() throws {
        let decision = try decide(jevResponse(choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9], recency: 0.99))
        #expect(decision.instinct == .stock)
        #expect(decision.source == .jev)
        #expect(decision.recent, "logged whatever the pick; only the answer instincts act on it")
    }

    @Test func unsureBeatsRecency() throws {
        #expect(try decide(jevResponse(choice: "narrative", confidence: 0.3, probabilities: ["narrative": 0.4], recency: 0.9)).source == .confidenceFallback)
    }

    @Test func floorIsInclusive() throws {
        let response = try response(choice: "narrative", confidence: 0.5, probabilities: ["narrative": 0.55, "web_results": 0.45])
        #expect(EngineRequest.decision(from: response, latencyMs: 1).source == .jev)
    }

    @Test func unknownOptionFallsBackToWeb() throws {
        let response = try response(choice: "podcasts", confidence: 0.9, probabilities: ["podcasts": 0.9])
        let decision = EngineRequest.decision(from: response, latencyMs: 1)
        #expect(decision.instinct == .webResults)
        #expect(decision.suggested == nil)
        if case .error = decision.source {} else { Issue.record("expected an error source") }
    }

    @Test func missingQuestionFallsBackToWebAndStillLogsTheRest() throws {
        let json = """
        { "model": "jev-1.13.0", "answers": { "x0": { "type": "noul", "noul": 0.9 }, "reasoning": { "type": "score", "score": 1.8, "confidence": 0.7, "probabilities": { "2": 0.8 } } }, "usage": { "input_tokens": 1, "output_tokens": 0 } }
        """
        let decision = try decide(json, exchanges: recipe)
        #expect(decision.instinct == .webResults)
        if case .error = decision.source {} else { Issue.record("expected an error source") }
        #expect(decision.relevance == [0.9] && decision.chain == 1 && decision.reasoning == 1.8, "what did come back is kept for the log")
    }

    // MARK: The chain

    @Test func aChainEndingOnAnAnswerGrowsIt() throws {
        let decision = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1, relevance: [0.8]), exchanges: recipe)
        #expect(decision.relevance == [0.8])
        #expect(decision.chain == 1)
        #expect(decision.instinct == .narrative)
        #expect(decision.source == .jev)
        #expect(decision.continues == true)
        #expect(decision.continuesThread)
    }

    @Test func overAnAnswerThePickIsStillJevs() throws {
        // "can I use water" over a recipe: a confident answer pick grows the
        // thread; a confident web pick is a search with the recipe as context;
        // an unsure pick is web results, as anywhere.
        let narrative = try decide(jevResponse(choice: "narrative", confidence: 0.8, probabilities: ["narrative": 0.8], relevance: [0.9]), exchanges: recipe)
        #expect(narrative.continuesThread && narrative.source == .jev)
        let web = try decide(jevResponse(choice: "web_results", confidence: 0.9, probabilities: ["web_results": 0.9], relevance: [0.9]), exchanges: recipe)
        #expect(web.instinct == .webResults && web.source == .jev && !web.continuesThread && web.chain == 1)
        for (choice, confidence) in [("web_results", 0.3), ("narrative", 0.2), ("one_line", 0.4), ("image", 0.3)] {
            let unsure = try decide(jevResponse(choice: choice, confidence: confidence, probabilities: [choice: 0.5], relevance: [0.9]), exchanges: recipe)
            #expect(unsure.instinct == .webResults && unsure.source == .confidenceFallback, "\(choice) at \(confidence)")
            #expect(!unsure.continuesThread)
            #expect(unsure.suggested == Instinct(rawValue: choice), "the pick is kept for the log")
        }
    }

    @Test func aConfidentOneLinePickIsAShortTurnOfTheThread() throws {
        // "and chile?" after "capital of peru": a one-line reply inside the conversation.
        let capital = answerExchanges([(query: "capital of peru", answer: "==Lima==")])
        let decision = try decide(jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.92, "narrative": 0.05], recency: 0.1, relevance: [0.9]), exchanges: capital)
        #expect(decision.instinct == .oneLine)
        #expect(decision.source == .jev)
        #expect(decision.continuesThread)
        let stale = try decide(jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.92], recency: 0.9, relevance: [0.9]), exchanges: capital)
        #expect(stale.continuesThread && stale.recent, "logged both ways; the answer instinct decides what to show")
    }

    @Test func aRelatedAskForAnotherCardGetsThatCard() throws {
        // "pictures of chocolate milk" after the recipe: related, and a picture.
        for format in Instinct.allCases where format.outranksConversation {
            let decision = try decide(jevResponse(choice: format.rawValue, confidence: 0.9, probabilities: [format.rawValue: 0.9], relevance: [0.9]), exchanges: recipe)
            #expect(decision.instinct == format, "\(format)")
            #expect(decision.source == .jev, "\(format)")
            #expect(decision.chain == 1, "the chain is still logged")
            #expect(!decision.continuesThread)
        }
    }

    @Test func theChainStopsAtTheFirstNoAndLogsEveryAnswer() throws {
        let three = answerExchanges([(query: "q1", answer: "a1"), (query: "q2", answer: "a2"), (query: "q3", answer: "a3")])
        let decision = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], relevance: [1, 0, 1]), exchanges: three)
        #expect(decision.relevance == [1, 0, 1], "oldest first, the yes behind the no kept")
        #expect(decision.chain == 1)
        #expect(decision.continuesThread)
        #expect(EngineRequest.chain([1, 1, 1]) == 3)
        #expect(EngineRequest.chain([1, 1, 0]) == 0)
        #expect(EngineRequest.chain([]) == 0)
        #expect(EngineRequest.chain([0.5]) == 1, "the threshold is inclusive")
        #expect(EngineRequest.chain([0.49]) == 0)
    }

    @Test func aChainEndingOnAPageKeepsThePickAndCountsTheChain() throws {
        // "wait no I meant brazil" after a search: web results, read with the correction.
        let web = try decide(jevResponse(choice: "web_results", confidence: 0.8, probabilities: ["web_results": 0.85], relevance: [0.9]), exchanges: search)
        #expect(web.instinct == .webResults)
        #expect(web.source == .jev)
        #expect(web.chain == 1)
        #expect(!web.continuesThread, "a search is not an answer to grow")
        // "how big is it" after reading a page: a narrative with the page as context.
        let page = [Exchange.page(query: "brasil weather", title: "Weather in Brasília", address: URL(string: "https://weather.com/br")!)]
        let narrative = try decide(jevResponse(choice: "narrative", confidence: 0.8, probabilities: ["narrative": 0.85], recency: 0.1, relevance: [0.9]), exchanges: page)
        #expect(narrative.instinct == .narrative)
        #expect(narrative.source == .jev)
        #expect(narrative.chain == 1)
        #expect(!narrative.continuesThread)
        // An unsure pick over a page still falls back to web.
        let unsure = try decide(jevResponse(choice: "narrative", confidence: 0.3, probabilities: ["narrative": 0.4], relevance: [0.9]), exchanges: page)
        #expect(unsure.source == .confidenceFallback)
    }

    @Test func relevanceThresholdIsInclusiveAndAMissingAnswerIsANo() throws {
        let at = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], relevance: [EngineRequest.relevanceThreshold]), exchanges: recipe)
        #expect(at.continuesThread && at.chain == 1)
        let under = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], relevance: [EngineRequest.relevanceThreshold - 0.01]), exchanges: recipe)
        #expect(!under.continuesThread)
        #expect(under.chain == 0)
        let unanswered = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9]), exchanges: recipe)
        #expect(unanswered.relevance == [0], "exchanges were sent, so the answers are logged, a missing one as a no")
        #expect(unanswered.chain == 0)
        #expect(unanswered.source == .jev && !unanswered.continuesThread, "a fresh narrative, not a thread")
    }

    @Test func belowTheThresholdTheUsualRulesHold() throws {
        let sure = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], relevance: [0.2]), exchanges: recipe)
        #expect(sure.instinct == .narrative)
        #expect(sure.source == .jev)
        #expect(!sure.continuesThread, "a fresh narrative, not a thread")
        let unsure = try decide(jevResponse(choice: "narrative", confidence: 0.3, probabilities: ["narrative": 0.4], relevance: [0.2]), exchanges: recipe)
        #expect(unsure.source == .confidenceFallback)
        let unasked = try response(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9])
        #expect(EngineRequest.decision(from: unasked, latencyMs: 1).relevance == nil)
        #expect(!EngineRequest.decision(from: unasked, latencyMs: 1).continuesThread)
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
        #expect(wanted.instinct == .webResults, "stage 1 still shows web results")
        #expect(wanted.reasoningWanted)
        let low = try decide(jevResponse(choice: "web_results", confidence: 0.3, probabilities: ["web_results": 0.4, "narrative": 0.3], reasoning: (score: 0.4, confidence: 0.9)))
        #expect(!low.reasoningWanted)
        let confident = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1, reasoning: (score: 1.9, confidence: 0.9)))
        #expect(confident.source == .jev && !confident.reasoningWanted, "a confident pick runs, whatever the score")
        #expect(try decide(jevResponse(choice: "web_results", confidence: 0.3, probabilities: ["web_results": 0.4], reasoning: (score: EngineRequest.reasoningThreshold, confidence: 0.5))).reasoningWanted, "inclusive")
    }

    @Test func theRememberGateIsReadOnEveryPickAndNeverGates() throws {
        let stated = try decide(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1, nouls: ["remember": 0.86]))
        #expect(stated.remember == 0.86)
        #expect(stated.statesFact)
        #expect(stated.instinct == .narrative && stated.source == .jev, "the pick runs as usual; the fact is noted beside it")
        let plain = try decide(jevResponse(choice: "web_results", confidence: 0.9, probabilities: ["web_results": 0.9], nouls: ["remember": 0.1]))
        #expect(!plain.statesFact)
        let unasked = try decide(jevResponse(choice: "web_results", confidence: 0.9, probabilities: ["web_results": 0.9]))
        #expect(unasked.remember == nil && !unasked.statesFact)
        #expect(try decide(jevResponse(choice: "remember", confidence: 0.9, probabilities: ["remember": 0.9], nouls: ["remember": EngineRequest.rememberThreshold])).statesFact, "inclusive")
        #expect(try JSONDecoder().decode(Pick.self, from: JSONEncoder().encode(stated)).remember == 0.86)
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
        let decision = Pick(
            instinct: .narrative, suggested: .narrative, confidence: 0.8, probabilities: ["narrative": 0.8],
            recency: 0.1, relevance: [0.2, 0.8], chain: 1, continues: true, reasoning: 0.3, reasoningConfidence: 0.7, source: .jev
        )
        #expect(try JSONDecoder().decode(Pick.self, from: JSONEncoder().encode(decision)) == decision)
        #expect(decision.continuesThread)
        let old = #"{"instinct":"narrative","probabilities":{},"source":{"jev":{}}}"#
        let decoded = try JSONDecoder().decode(Pick.self, from: Data(old.utf8))
        #expect(decoded.relevance == nil && decoded.chain == nil && decoded.reasoning == nil && decoded.continues == nil)
        #expect(!decoded.continuesThread)
        let versionOne = #"{"instinct":"narrative","probabilities":{},"continuation":0.8,"source":{"continuation":{}}}"#
        #expect(throws: (any Error).self, "a version 1 line, with its gate as the source, no longer reads; the lenient parse skips it") {
            try JSONDecoder().decode(Pick.self, from: Data(versionOne.utf8))
        }
    }

    @Test func decisionRoundTripsThroughJSON() throws {
        let decision = Pick(
            instinct: .webResults, suggested: .oneLine, confidence: 0.3,
            probabilities: ["one_line": 0.37, "web_results": 0.33], model: "jev-1.13.0",
            latencyMs: 150, inputTokens: 500, source: .confidenceFallback
        )
        let data = try JSONEncoder().encode(decision)
        #expect(try JSONDecoder().decode(Pick.self, from: data) == decision)
        let error = Pick(instinct: .webResults, source: .error("http 401: bad key"))
        #expect(try JSONDecoder().decode(Pick.self, from: JSONEncoder().encode(error)) == error)
    }
}

@Suite struct SiteDecisionTests {
    private func decision(_ json: String, exchanges: [Exchange] = []) throws -> Pick {
        EngineRequest.decision(from: try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8)), latencyMs: 1, exchanges: exchanges)
    }

    @Test func aConfidentSitePickPasses() throws {
        let decision = try decision(jevResponse(choice: "site", confidence: 0.9, probabilities: ["site": 0.91, "web_results": 0.06, "recall": 0.03], recency: 0.1))
        #expect(decision.instinct == .site)
        #expect(decision.source == .jev)
        #expect(decision.rejection == nil)
        #expect(!decision.rejectsSite)
    }

    @Test func anUnsureSitePickFallsBackLikeAnyFormat() throws {
        let decision = try decision(jevResponse(choice: "site", confidence: 0.4, probabilities: ["site": 0.45, "web_results": 0.4], recency: 0.1))
        #expect(decision.instinct == .webResults)
        #expect(decision.suggested == .site)
        #expect(decision.source == .confidenceFallback)
    }

    @Test func aRejectionIsLoggedBesideThePick() throws {
        // "no not this one" over zillow: the site criterion says it is a site
        // request again, so a sure pick is site; the rejection rides along
        // and the site instinct forgets the name and shows the choices.
        let sure = try decision(jevResponse(choice: "site", confidence: 0.8, probabilities: ["site": 0.82, "web_results": 0.1], recency: 0.2, rejects: 0.92))
        #expect(sure.instinct == .site)
        #expect(sure.source == .jev)
        #expect(sure.rejection == 0.92)
        #expect(sure.rejectsSite)
        let unsure = try decision(jevResponse(choice: "web_results", confidence: 0.1, probabilities: ["web_results": 0.3, "narrative": 0.28, "site": 0.1], recency: 0.2, rejects: 0.92))
        #expect(unsure.instinct == .webResults && unsure.source == .confidenceFallback, "nothing overrules the pick")
        #expect(unsure.rejectsSite, "still logged")
    }

    @Test func aRejectionIsLoggedBesideTheChain() throws {
        let page = [Exchange.page(query: "pull up zillow", title: "Zillow", address: URL(string: "https://www.zillow.com/")!)]
        let decision = try decision(jevResponse(choice: "site", confidence: 0.8, probabilities: ["site": 0.8], rejects: 0.9, relevance: [0.95]), exchanges: page)
        #expect(decision.rejectsSite)
        #expect(decision.chain == 1, "still logged")
        #expect(!decision.continuesThread, "a page is not an answer to grow")
    }

    @Test func belowTheRejectionThresholdTheOrdinaryRulesApply() throws {
        let fresh = try decision(jevResponse(choice: "site", confidence: 0.9, probabilities: ["site": 0.92, "web_results": 0.08], recency: 0.1, rejects: 0.2))
        #expect(fresh.instinct == .site)
        #expect(fresh.source == .jev, "\"open youtube\" over zillow is a new site request, not a rejection")
        #expect(fresh.rejection == 0.2)
        let question = try decision(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.92, "web_results": 0.08], recency: 0.1, rejects: 0.05))
        #expect(question.instinct == .narrative)
        #expect(question.source == .jev)
    }

    @Test func theRejectionThresholdIsInclusive() throws {
        let at = try decision(jevResponse(choice: "site", confidence: 0.8, probabilities: ["site": 0.8], rejects: EngineRequest.rejectionThreshold))
        #expect(at.rejectsSite)
        let under = try decision(jevResponse(choice: "site", confidence: 0.8, probabilities: ["site": 0.8], rejects: EngineRequest.rejectionThreshold - 0.01))
        #expect(!under.rejectsSite)
    }
}
