import Foundation
import Testing
@testable import Routing

/// The gate into advanced reasoning and the bounds a plan runs within.
@Suite struct ReasoningPolicyTests {
    private func decision(_ score: Double?, source: RouteDecision.Source = .jev, format: ResponseFormat = .narrative) -> RouteDecision {
        RouteDecision(format: format, suggested: format, confidence: 0.8, probabilities: [format.rawValue: 0.8], model: "jev-1.13.0", latencyMs: 100, inputTokens: 100, reasoning: score, source: source)
    }

    @Test func aScoreAtTheThresholdEntersWhateverThePick() {
        #expect(ReasoningPolicy.entersReasoning(decision(1.5)))
        #expect(ReasoningPolicy.entersReasoning(decision(2.0, format: .webResults)))
        #expect(!ReasoningPolicy.entersReasoning(decision(1.49)))
        #expect(!ReasoningPolicy.entersReasoning(decision(0.2)))
    }

    @Test func anUnsurePickEntersFromTheLeanThreshold() {
        #expect(ReasoningPolicy.entersReasoning(decision(1.0, source: .confidenceFallback)))
        #expect(ReasoningPolicy.entersReasoning(decision(1.2, source: .confidenceFallback)))
        #expect(!ReasoningPolicy.entersReasoning(decision(0.9, source: .confidenceFallback)))
        #expect(!ReasoningPolicy.entersReasoning(decision(1.2, source: .jev)), "a sure pick needs the full score")
    }

    @Test func withoutAScoreNothingEnters() {
        #expect(!ReasoningPolicy.entersReasoning(decision(nil)))
        #expect(!ReasoningPolicy.entersReasoning(.directURL()))
        #expect(!ReasoningPolicy.entersReasoning(.local("time", format: .oneLine)))
    }

    @Test func paidAndDestructiveStepsAreConfirmedUnlessTheyAsk() {
        #expect(!ReasoningPolicy.needsConfirmation(InstinctSpec.spec(for: .narrative)))
        #expect(!ReasoningPolicy.needsConfirmation(InstinctSpec.spec(for: .remember)), "reversible by forget")
        #expect(!ReasoningPolicy.needsConfirmation(InstinctSpec.spec(for: .forget)), "it puts its own question")
        #expect(InstinctSpec.spec(for: .forget).asksItself)
        let paid = InstinctSpec(format: .webResults, sideEffects: .paid)
        #expect(ReasoningPolicy.needsConfirmation(paid))
        let destructive = InstinctSpec(format: .webResults, sideEffects: .destructive)
        #expect(ReasoningPolicy.needsConfirmation(destructive))
        #expect(!ReasoningPolicy.needsConfirmation(InstinctSpec(format: .webResults, sideEffects: .destructive, asksItself: true)))
    }

    @Test func aStepIsItsNameAndItsArguments() {
        let a = ReasoningPolicy.stepKey(name: "narrative", arguments: ["query": "dinner", "count": 2])
        let same = ReasoningPolicy.stepKey(name: "narrative", arguments: ["count": 2, "query": "dinner"])
        let other = ReasoningPolicy.stepKey(name: "narrative", arguments: ["query": "lunch"])
        #expect(a == same, "key order does not matter")
        #expect(a != other)
        #expect(a != ReasoningPolicy.stepKey(name: "one_line", arguments: ["query": "dinner", "count": 2]))
    }

    @Test func theBoundsAreTheDocumentedOnes() {
        #expect(ReasoningPolicy.maxRounds == 4)
        #expect(ReasoningPolicy.timeBudget == .seconds(20))
        #expect(ReasoningPolicy.roundTimeout == .seconds(8))
        #expect(ReasoningPolicy.memoriesGiven == 5)
        #expect(ReasoningPolicy.threshold == EngineRouting.reasoningThreshold)
    }

    @Test func theSummaryReadsItsSteps() throws {
        let summary = EngineSummary(
            model: "gemini-3.8-flash", rounds: 2,
            steps: [
                .init(name: "remember", arguments: ["query": "I'm vegetarian", "fact": "I'm vegetarian"], outcome: "ran", latencyMs: 12),
                .init(name: "narrative", arguments: ["query": "a vegetarian dinner"], outcome: "shown", latencyMs: 900),
                .init(name: "done", arguments: [:], outcome: "done", latencyMs: 0),
            ],
            usage: AnswerUsage(inputTokens: 2000, outputTokens: 80, thoughtTokens: 40), latencyMs: 3000, factsGiven: 1, memoriesGiven: 0, outcome: .completed
        )
        #expect(summary.shownSomething && summary.didSomething)
        let data = try DecisionRecord.encoder.encode(summary)
        let back = try DecisionRecord.decoder.decode(EngineSummary.self, from: data)
        #expect(back == summary)
        let fell = EngineSummary(model: "m", rounds: 1, steps: [], latencyMs: 10, factsGiven: 0, memoriesGiven: 0, outcome: .fellBackToWeb("no calls"))
        #expect(!fell.shownSomething && !fell.didSomething)
        #expect(try DecisionRecord.decoder.decode(EngineSummary.self, from: DecisionRecord.encoder.encode(fell)).outcome == .fellBackToWeb("no calls"))
    }

    @Test func aPlanStepIsItsOwnSourceAndRoundTrips() throws {
        let step = RouteDecision(format: .narrative, suggested: nil, confidence: 1, source: .plan)
        #expect(!ReasoningPolicy.entersReasoning(step), "a step never plans again")
        let back = try DecisionRecord.decoder.decode(RouteDecision.self, from: DecisionRecord.encoder.encode(step))
        #expect(back.source == .plan && back.suggested == nil)
    }

    @Test func flashCostsMoreThanLite() {
        let usage = AnswerUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, thoughtTokens: 0)
        #expect(GeminiPricing.cost(usage, model: "gemini-3.1-flash-lite") == 1.75)
        #expect(GeminiPricing.cost(usage, model: "gemini-3.8-flash") == 4.50)
        let plan = AnswerUsage(inputTokens: 9000, outputTokens: 300, thoughtTokens: 300)
        #expect(GeminiPricing.cost(plan, model: "gemini-3.8-flash") < 0.011, "three rounds of a plan stay around a cent")
    }
}
