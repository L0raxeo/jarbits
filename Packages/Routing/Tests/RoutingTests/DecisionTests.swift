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

    @Test func confidentAnswerPassesTheGate() throws {
        let response = try response(choice: "stock", confidence: 0.91, probabilities: ["stock": 0.92, "web_results": 0.05, "narrative": 0.03])
        let decision = JevRouting.decision(from: response, latencyMs: 212)
        #expect(decision.format == .stock)
        #expect(decision.suggested == .stock)
        #expect(decision.source == .jev)
        #expect(decision.confidence == 0.91)
        #expect(decision.latencyMs == 212)
        #expect(decision.inputTokens == 512)
        #expect(decision.model == "jev-1.13.0")
        #expect(decision.runnerUp?.format == .webResults)
    }

    @Test func recallPassesTheGateLikeAnyFormat() throws {
        let sure = try response(choice: "recall", confidence: 0.88, probabilities: ["recall": 0.88, "web_results": 0.1, "narrative": 0.02])
        #expect(JevRouting.decision(from: sure, latencyMs: 1).format == .recall)
        let unsure = try response(choice: "recall", confidence: 0.45, probabilities: ["recall": 0.45, "web_results": 0.4, "narrative": 0.15])
        let decision = JevRouting.decision(from: unsure, latencyMs: 1)
        #expect(decision.format == .webResults)
        #expect(decision.suggested == .recall)
        #expect(decision.source == .confidenceFallback)
    }

    @Test func unsureAnswerFallsBackToWeb() throws {
        let response = try response(choice: "map", confidence: 0.4, probabilities: ["map": 0.46, "web_results": 0.3, "narrative": 0.24])
        let decision = JevRouting.decision(from: response, latencyMs: 180)
        #expect(decision.format == .webResults)
        #expect(decision.suggested == .map)
        #expect(decision.source == .confidenceFallback)
    }

    @Test func recentAnswerFormatIsSentToWeb() throws {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(jevResponse(
            choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.92, "web_results": 0.08], recency: 0.8).utf8))
        let decision = JevRouting.decision(from: response, latencyMs: 1)
        #expect(decision.format == .webResults)
        #expect(decision.suggested == .narrative)
        #expect(decision.recency == 0.8)
        #expect(decision.source == .recencyFallback)
    }

    @Test func settledAnswerFormatPasses() throws {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(jevResponse(
            choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.92], recency: 0.2).utf8))
        let decision = JevRouting.decision(from: response, latencyMs: 1)
        #expect(decision.format == .oneLine)
        #expect(decision.source == .jev)
        #expect(decision.recency == 0.2)
    }

    @Test func recencyThresholdIsInclusive() throws {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(jevResponse(
            choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: JevRouting.recencyThreshold).utf8))
        #expect(JevRouting.decision(from: response, latencyMs: 1).source == .recencyFallback)
    }

    @Test func missingRecencyNeverGates() throws {
        let response = try response(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9])
        let decision = JevRouting.decision(from: response, latencyMs: 1)
        #expect(decision.source == .jev)
        #expect(decision.recency == nil)
    }

    @Test func pageFormatsIgnoreRecency() throws {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(jevResponse(
            choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9], recency: 0.99).utf8))
        let decision = JevRouting.decision(from: response, latencyMs: 1)
        #expect(decision.format == .stock)
        #expect(decision.source == .jev)
    }

    @Test func unsureBeatsRecency() throws {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(jevResponse(
            choice: "narrative", confidence: 0.3, probabilities: ["narrative": 0.4], recency: 0.9).utf8))
        #expect(JevRouting.decision(from: response, latencyMs: 1).source == .confidenceFallback)
    }

    @Test func floorIsInclusive() throws {
        let response = try response(choice: "narrative", confidence: 0.5, probabilities: ["narrative": 0.55, "web_results": 0.45])
        #expect(JevRouting.decision(from: response, latencyMs: 1).source == .jev)
    }

    @Test func unknownOptionFallsBackToWeb() throws {
        let response = try response(choice: "podcasts", confidence: 0.9, probabilities: ["podcasts": 0.9])
        let decision = JevRouting.decision(from: response, latencyMs: 1)
        #expect(decision.format == .webResults)
        #expect(decision.suggested == nil)
        if case .error = decision.source {} else { Issue.record("expected an error source") }
    }

    @Test func missingQuestionFallsBackToWeb() throws {
        let json = """
        { "model": "jev-1.13.0", "answers": {}, "usage": { "input_tokens": 1, "output_tokens": 0 } }
        """
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8))
        let decision = JevRouting.decision(from: response, latencyMs: 1)
        #expect(decision.format == .webResults)
        if case .error = decision.source {} else { Issue.record("expected an error source") }
    }

    private func decode(_ json: String) throws -> SystemOneResponse {
        try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8))
    }

    @Test func aContinuedNarrativeGrowsTheThread() throws {
        let response = try decode(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1, continues: 0.8))
        let decision = JevRouting.decision(from: response, latencyMs: 1)
        #expect(decision.continuation == 0.8)
        #expect(decision.format == .narrative)
        #expect(decision.source == .continuation)
        #expect(decision.continuesThread)
    }

    @Test func aTerseReplyThreadsWhateverItLookedLikeOnItsOwn() throws {
        // "can I use water": flat and web first, a confident web pick, an unsure one-liner, an unsure picture.
        for (choice, confidence) in [("web_results", 0.3), ("web_results", 0.9), ("narrative", 0.2), ("one_line", 0.4), ("image", 0.3)] {
            let response = try decode(jevResponse(choice: choice, confidence: confidence, probabilities: [choice: 0.5], continues: 0.9))
            let decision = JevRouting.decision(from: response, latencyMs: 1)
            #expect(decision.format == .narrative, "\(choice) at \(confidence)")
            #expect(decision.source == .continuation, "\(choice) at \(confidence)")
            #expect(decision.suggested == ResponseFormat(rawValue: choice), "the pick is kept for the log")
        }
    }

    @Test func aConfidentOneLinePickIsAShortTurnOfTheThread() throws {
        // "and chile?" after "capital of peru": a one-line reply inside the conversation.
        let response = try decode(jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.92, "narrative": 0.05], recency: 0.1, continues: 0.9))
        let decision = JevRouting.decision(from: response, latencyMs: 1)
        #expect(decision.format == .oneLine)
        #expect(decision.source == .continuation)
        #expect(decision.continuesThread)
        let stale = try decode(jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.92], recency: 0.9, continues: 0.9))
        #expect(JevRouting.decision(from: stale, latencyMs: 1).source == .recencyFallback, "a short reply that needs live data still goes to web")
    }

    @Test func aRelatedAskForAnotherCardGetsThatCard() throws {
        // "pictures of chocolate milk" after the recipe: related, and a picture.
        for format in ResponseFormat.allCases where format.outranksConversation {
            let response = try decode(jevResponse(choice: format.rawValue, confidence: 0.9, probabilities: [format.rawValue: 0.9], continues: 0.9))
            let decision = JevRouting.decision(from: response, latencyMs: 1)
            #expect(decision.format == format, "\(format)")
            #expect(decision.source == .jev, "\(format)")
            #expect(!decision.continuesThread)
        }
    }

    @Test func aStaleContinuationStillGoesToWeb() throws {
        let response = try decode(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.9, continues: 0.95))
        let decision = JevRouting.decision(from: response, latencyMs: 1)
        #expect(decision.format == .webResults)
        #expect(decision.source == .recencyFallback)
        #expect(!decision.continuesThread)
    }

    @Test func continuationThresholdIsInclusive() throws {
        let at = try decode(jevResponse(choice: "web_results", confidence: 0.3, probabilities: ["web_results": 0.4], continues: JevRouting.continuationThreshold))
        #expect(JevRouting.decision(from: at, latencyMs: 1).source == .continuation)
        let under = try decode(jevResponse(choice: "web_results", confidence: 0.3, probabilities: ["web_results": 0.4], continues: JevRouting.continuationThreshold - 0.01))
        #expect(JevRouting.decision(from: under, latencyMs: 1).source == .confidenceFallback)
    }

    @Test func belowTheThresholdTheUsualRulesHold() throws {
        let sure = try decode(jevResponse(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], continues: 0.2))
        let decision = JevRouting.decision(from: sure, latencyMs: 1)
        #expect(decision.format == .narrative)
        #expect(decision.source == .jev)
        #expect(!decision.continuesThread, "a fresh narrative, not a thread")
        let unsure = try decode(jevResponse(choice: "narrative", confidence: 0.3, probabilities: ["narrative": 0.4], continues: 0.2))
        #expect(JevRouting.decision(from: unsure, latencyMs: 1).source == .confidenceFallback)
        let unasked = try response(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9])
        #expect(JevRouting.decision(from: unasked, latencyMs: 1).continuation == nil)
        #expect(!JevRouting.decision(from: unasked, latencyMs: 1).continuesThread)
    }

    @Test func continuationRoundTripsAndOldLinesDecode() throws {
        let decision = RouteDecision(
            format: .narrative, suggested: .webResults, confidence: 0.3, probabilities: ["web_results": 0.4],
            recency: 0.1, continuation: 0.8, source: .continuation
        )
        #expect(try JSONDecoder().decode(RouteDecision.self, from: JSONEncoder().encode(decision)) == decision)
        let old = #"{"format":"narrative","probabilities":{},"source":{"jev":{}}}"#
        let decoded = try JSONDecoder().decode(RouteDecision.self, from: Data(old.utf8))
        #expect(decoded.continuation == nil)
        #expect(!decoded.continuesThread)
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
    private func decision(_ json: String) throws -> RouteDecision {
        JevRouting.decision(from: try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8)), latencyMs: 1)
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
        let decision = try decision(jevResponse(choice: "web_results", confidence: 0.2, probabilities: ["web_results": 0.4], rejects: JevRouting.rejectionThreshold))
        #expect(decision.source == .rejection)
    }
}
