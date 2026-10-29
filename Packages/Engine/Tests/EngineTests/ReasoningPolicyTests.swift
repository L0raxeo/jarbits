import Foundation
import Testing
@testable import Engine

/// The gate into advanced reasoning and the bounds a plan runs within.
@Suite struct ReasoningPolicyTests {
    private func decision(_ score: Double?, source: Pick.Source = .jev, format: Instinct = .narrative) -> Pick {
        Pick(instinct: format, suggested: format, confidence: 0.8, probabilities: [format.rawValue: 0.8], model: "jev-1.13.0", latencyMs: 100, inputTokens: 100, reasoning: score, source: source)
    }

    @Test func aScoreAtTheThresholdEntersWhateverThePick() {
        #expect(ReasoningPolicy.entersReasoning(decision(ReasoningPolicy.threshold)))
        #expect(ReasoningPolicy.entersReasoning(decision(1.46)), "the two-step remember-then-suggest measured 1.46 (2026-10-27)")
        #expect(ReasoningPolicy.entersReasoning(decision(2.0, format: .webResults)))
        #expect(!ReasoningPolicy.entersReasoning(decision(ReasoningPolicy.threshold - 0.01)))
        #expect(!ReasoningPolicy.entersReasoning(decision(0.82)), "a plain remember measured 0.82")
        #expect(!ReasoningPolicy.entersReasoning(decision(0.2)))
    }

    @Test func anInstinctWithoutTheShortcutEntersOnASurePick() {
        let notebook = InstinctSpec.spec(for: .notebook)
        let search = InstinctSpec.spec(for: .webResults)
        #expect(!notebook.shortcut && search.shortcut)
        #expect(ReasoningPolicy.entersReasoning(decision(0.2, format: .notebook), spec: notebook), "reasoned, whatever the score")
        #expect(!ReasoningPolicy.entersReasoning(decision(0.2, format: .webResults), spec: search))
        #expect(!ReasoningPolicy.entersReasoning(decision(0.2, format: .notebook)), "without the spec the old rule stands, for the eval")
        #expect(InstinctSpec.all.filter { !$0.shortcut }.map(\.id) == ["map", "stock", "notebook"], "the unbuilt two and the notebook are reasoned; the rest earned the shortcut")
    }

    @Test func anUnsurePickAlwaysEnters() {
        #expect(ReasoningPolicy.entersReasoning(decision(1.0, source: .confidenceFallback)))
        #expect(ReasoningPolicy.entersReasoning(decision(0.2, source: .confidenceFallback)))
        #expect(ReasoningPolicy.entersReasoning(decision(nil, source: .confidenceFallback)), "whatever the score, or none")
        #expect(!ReasoningPolicy.entersReasoning(decision(1.1, source: .jev)), "a sure pick needs the full score")
    }

    @Test func withoutAScoreNothingEnters() {
        #expect(!ReasoningPolicy.entersReasoning(decision(nil)))
        #expect(!ReasoningPolicy.entersReasoning(.directURL()))
    }

    @Test func paidAndDestructiveStepsAreConfirmedUnlessTheyAsk() {
        #expect(!ReasoningPolicy.needsConfirmation(InstinctSpec.spec(for: .narrative)))
        #expect(!ReasoningPolicy.needsConfirmation(InstinctSpec.spec(for: .remember)), "reversible by forget")
        #expect(!ReasoningPolicy.needsConfirmation(InstinctSpec.spec(for: .forget)), "it puts its own question")
        #expect(InstinctSpec.spec(for: .forget).asksItself)
        let paid = InstinctSpec(instinct: .webResults, sideEffects: .paid)
        #expect(ReasoningPolicy.needsConfirmation(paid))
        let destructive = InstinctSpec(instinct: .webResults, sideEffects: .destructive)
        #expect(ReasoningPolicy.needsConfirmation(destructive))
        #expect(!ReasoningPolicy.needsConfirmation(InstinctSpec(instinct: .webResults, sideEffects: .destructive, asksItself: true)))
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
        #expect(ReasoningPolicy.maxRounds == 6)
        #expect(ReasoningPolicy.timeBudget == .seconds(120))
        #expect(ReasoningPolicy.roundTimeout == .seconds(45))
        #expect(ReasoningPolicy.memoriesGiven == 5)
        #expect(ReasoningPolicy.threshold == EngineRequest.reasoningThreshold)
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
        let step = Pick(instinct: .narrative, suggested: nil, confidence: 1, source: .plan)
        #expect(!ReasoningPolicy.entersReasoning(step), "a step never plans again")
        let back = try DecisionRecord.decoder.decode(Pick.self, from: DecisionRecord.encoder.encode(step))
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
