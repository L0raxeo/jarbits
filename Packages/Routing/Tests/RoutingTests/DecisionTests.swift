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
