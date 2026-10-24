import Foundation
import Testing
@testable import Evals
@testable import Routing

@Suite struct EvalReportTests {
    @Test func theReportNamesTheMissesTheGatesAndTheCounts() throws {
        let results = [
            EvalResult(EvalCase(query: "eiffel tower", format: .image), outcome: RouteOutcome(query: "eiffel tower", decision: try decision(choice: "image", confidence: 0.42, probabilities: ["image": 0.46, "web_results": 0.41, "narrative": 0.09, "map": 0.04])), cached: true),
            EvalResult(EvalCase(query: "look up steve jobs", format: .webResults, source: "local:search"), outcome: RouteOutcome(query: "look up steve jobs", decision: .local("search", format: .webResults)), cached: false),
            EvalResult(EvalCase(query: "apple.com", format: .webResults), outcome: RouteOutcome(query: "apple.com", decision: .directURL()), cached: false),
            EvalResult(EvalCase(query: "tesla stock", format: .stock), outcome: RouteOutcome(query: "tesla stock", decision: try decision(choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9])), cached: false),
            .uncached(EvalCase(query: "news", format: .webResults)),
        ]
        let text = EvalReport.text(results: results, file: "Evals/routing.jsonl", floor: 0.5, recencyThreshold: 0.5, model: "jev-1.13.0")
        #expect(text.contains("eval Evals/routing.jsonl: 5 cases, 3 passed, 1 failed, 1 not cached (floor 0.5, recency 0.5, jev-1.13.0; 1 on the device, 1 address, 1 from cache, 1 asked Jev, 1 not cached)"))
        #expect(text.contains("  \"eiffel tower\"\n      format: expected image, got web_results (confidenceFallback)\n      confidence 0.42 < 0.5   image .46  web_results .41  narrative .09"))
        #expect(text.contains("  \"news\"\n      not cached"))
        #expect(text.contains("  web_results   2/3"))
        #expect(text.contains("  stock         1/1"))
        #expect(text.contains("  image         0/1"))
    }

    @Test func gatesNameTheDecisiveThreshold() throws {
        #expect(EvalReport.gate(.local("time", format: .oneLine), floor: 0.5, recencyThreshold: 0.5) == "device rule time")
        #expect(EvalReport.gate(.directURL(), floor: 0.5, recencyThreshold: 0.5) == "address")
        #expect(EvalReport.gate(try decision(choice: "narrative", confidence: 0.92, probabilities: ["narrative": 0.93], recency: 0.9), floor: 0.5, recencyThreshold: 0.5) == "recency 0.90 ≥ 0.5, confidence 0.92 ≥ 0.5")
        #expect(EvalReport.gate(try decision(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1, continues: 0.83), floor: 0.5, recencyThreshold: 0.5) == "continues 0.83 ≥ 0.5, confidence 0.90 ≥ 0.5")
        #expect(EvalReport.gate(try decision(choice: "recall", confidence: 0.6, probabilities: ["recall": 0.7], rejects: 0.93), floor: 0.5, recencyThreshold: 0.5) == "rejects 0.93 ≥ 0.5")
        #expect(EvalReport.gate(try decision(choice: "image", confidence: 0.9, probabilities: ["image": 0.9], continues: 0.8), floor: 0.5, recencyThreshold: 0.5) == "confidence 0.90 ≥ 0.5, continues 0.80 ≥ 0.5")
        #expect(EvalReport.gate(RouteDecision(format: .webResults, source: .error("timeout")), floor: 0.5, recencyThreshold: 0.5) == "error: timeout")
    }

    @Test func theDiffReadsAsFlips() throws {
        let before = EvalResult(EvalCase(query: "reddit", format: .site), outcome: RouteOutcome(query: "reddit", decision: try decision(choice: "site", confidence: 0.4, probabilities: ["site": 0.45, "web_results": 0.4])), cached: true)
        let after = EvalResult(EvalCase(query: "reddit", format: .site), outcome: RouteOutcome(query: "reddit", decision: try decision(choice: "site", confidence: 0.9, probabilities: ["site": 0.9])), cached: false)
        let diff = EvalDiff(regressions: [], fixes: [EvalDiff.Flip(name: "reddit", before: before, after: after)], added: ["new one"], dropped: [])
        let text = EvalReport.text(diff: diff, baseline: "before.jsonl")
        #expect(text.contains("against before.jsonl: 0 regressions, 1 fix, 1 new, 0 dropped"))
        #expect(text.contains("  fixes:\n    \"reddit\": was web_results (confidenceFallback), now site (jev)"))
        #expect(text.contains("  new: \"new one\""))
    }
}
