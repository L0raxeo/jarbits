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
        let response = try response(choice: "stock", confidence: 0.91, probabilities: ["stock": 0.92, "web_results": 0.05, "links": 0.03])
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
        let response = try response(choice: "map", confidence: 0.4, probabilities: ["map": 0.46, "web_results": 0.3, "images": 0.24])
        let decision = JevRouting.decision(from: response, latencyMs: 180)
        #expect(decision.format == .webResults)
        #expect(decision.suggested == .map)
        #expect(decision.source == .confidenceFallback)
    }

    @Test func floorIsInclusive() throws {
        let response = try response(choice: "videos", confidence: 0.5, probabilities: ["videos": 0.55, "web_results": 0.45])
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
            format: .webResults, suggested: .flights, confidence: 0.3,
            probabilities: ["flights": 0.37, "web_results": 0.33], model: "jev-1.13.0",
            latencyMs: 150, inputTokens: 500, source: .confidenceFallback
        )
        let data = try JSONEncoder().encode(decision)
        #expect(try JSONDecoder().decode(RouteDecision.self, from: data) == decision)
        let error = RouteDecision(format: .webResults, source: .error("http 401: bad key"))
        #expect(try JSONDecoder().decode(RouteDecision.self, from: JSONEncoder().encode(error)) == error)
    }
}
