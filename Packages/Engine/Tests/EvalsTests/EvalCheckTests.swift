import Foundation
import Testing
@testable import Evals
@testable import Engine

@Suite struct EvalCheckTests {
    @Test func theRightFormatPasses() throws {
        let decision = try decision(choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9])
        #expect(EvalCheck.failures(EvalCase(query: "tesla stock", instinct: .stock), decision).isEmpty)
    }

    @Test func webResultsViaAFallbackPassUnlessTheSourceIsPinned() throws {
        let unsure = try decision(choice: "map", confidence: 0.4, probabilities: ["map": 0.46, "web_results": 0.3])
        #expect(EvalCheck.failures(EvalCase(query: "coffee near me", instinct: .webResults), unsure).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "coffee near me", instinct: .webResults, source: "jev"), unsure) == ["source: expected jev, got confidenceFallback"])
        #expect(EvalCheck.failures(EvalCase(query: "coffee near me", instinct: .map), unsure) == ["instinct: expected map, got web_results (confidenceFallback)"])
    }

    @Test func aPickIsCheckedApartFromTheFormat() throws {
        let unsure = try decision(choice: "narrative", confidence: 0.3, probabilities: ["narrative": 0.4, "web_results": 0.3])
        #expect(EvalCheck.failures(EvalCase(query: "is south africa safe right now", instinct: .webResults, pick: .narrative, source: "confidenceFallback"), unsure).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "is south africa safe right now", instinct: .webResults, pick: .oneLine), unsure) == ["pick: expected one_line, got narrative"])
    }

    @Test func aRecentAnswerPickIsStillThePick() throws {
        // The answer instinct shows web results for it; the eval grades the pick.
        let stale = try decision(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.8)
        #expect(EvalCheck.failures(EvalCase(query: "is south africa safe right now", instinct: .narrative), stale).isEmpty)
        #expect(stale.recent)
    }

    @Test func aRecallExpectationIsCheckedAgainstTheIntent() throws {
        let judged = try decision(choice: "recall", confidence: 0.9, probabilities: ["recall": 0.9], nouls: recallNouls(kinds: [.videos], named: true, all: false))
        #expect(EvalCheck.failures(EvalCase(query: "the video I was watching about muse", instinct: .recall, recall: RecallExpectation(kinds: [.videos], named: true, all: false)), judged).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "the video I was watching about muse", instinct: .recall, recall: RecallExpectation(kinds: [.pages], named: false)), judged) == [
            "recall kinds: expected [pages], got [videos]",
            "recall named: expected false, got true (1.00)",
        ])
        let unjudged = try decision(choice: "recall", confidence: 0.9, probabilities: ["recall": 0.9])
        #expect(EvalCheck.failures(EvalCase(query: "x", instinct: .recall, recall: RecallExpectation(named: true)), unjudged) == ["recall: expected an intent, got none"])
        let wrongFormat = try decision(choice: "web_results", confidence: 0.9, probabilities: ["web_results": 0.9])
        #expect(EvalCheck.failures(EvalCase(query: "x", instinct: .recall, recall: RecallExpectation(named: true)), wrongFormat) == ["instinct: expected recall, got web_results (jev)"], "only once the format is right")
    }

    @Test func anAddressLoadsAsTyped() {
        #expect(EvalCheck.failures(EvalCase(query: "apple.com", instinct: .webResults, source: "directURL"), .directURL()).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "apple.com", instinct: .site), .directURL()) == ["instinct: expected site, got web_results (directURL)"])
    }

    @Test func theChainIsCheckedOnceTheFormatIsRight() throws {
        let recipe = [Exchange.answer(query: "how do you make hot chocolate", text: "Heat milk.")]
        let continued = try decision(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1, relevance: [0.8], exchanges: recipe)
        #expect(EvalCheck.failures(EvalCase(query: "why?", exchanges: recipe, instinct: .narrative, chain: 1), continued).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "why?", exchanges: recipe, instinct: .narrative), continued).isEmpty, "no expectation, any chain")
        let fresh = try decision(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.9], recency: 0.1, relevance: [0.1], exchanges: recipe)
        #expect(EvalCheck.failures(EvalCase(query: "capital of peru", exchanges: recipe, instinct: .oneLine, chain: 0), fresh).isEmpty)
        #expect(EvalCheck.failures(EvalCase(query: "capital of peru", exchanges: recipe, instinct: .oneLine, chain: 1), fresh) == ["chain: expected 1, got 0 (newest relevance 0.10)"])
        let wrongFormat = try decision(choice: "image", confidence: 0.9, probabilities: ["image": 0.9], relevance: [0.1], exchanges: recipe)
        #expect(EvalCheck.failures(EvalCase(query: "why?", exchanges: recipe, instinct: .narrative, chain: 1), wrongFormat) == ["instinct: expected narrative, got image (jev)"], "only once the format is right")
    }

    @Test func anErrorNeverPasses() {
        let failed = Pick(instinct: .webResults, source: .error("timeout"))
        #expect(EvalCheck.failures(EvalCase(query: "news", instinct: .webResults), failed) == ["error: timeout"])
        #expect(EvalCheck.failures(EvalCase(query: "news", instinct: .webResults), .noKey()) == ["no key: Jev was not asked"])
    }
}
