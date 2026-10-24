import Foundation
import Testing
@testable import Evals
@testable import Routing

@Suite struct EvalDiffTests {
    private func result(_ query: String, expected: ResponseFormat, got: ResponseFormat, status: EvalStatus? = nil) -> EvalResult {
        var result = EvalResult(EvalCase(query: query, format: expected), outcome: RouteOutcome(query: query, decision: RouteDecision(format: got, suggested: got, confidence: 0.9, source: .jev)), cached: true)
        if let status { result.status = status }
        return result
    }

    @Test func flipsAreReportedByName() {
        let baseline = [
            result("eiffel tower", expected: .image, got: .image),
            result("reddit", expected: .site, got: .webResults),
            result("news", expected: .webResults, got: .webResults),
            result("old one", expected: .map, got: .map),
        ]
        let current = [
            result("eiffel tower", expected: .image, got: .webResults),
            result("reddit", expected: .site, got: .site),
            result("news", expected: .webResults, got: .webResults),
            result("new one", expected: .stock, got: .stock),
        ]
        let diff = EvalDiff.compare(baseline: baseline, current: current)
        #expect(diff.regressions.map(\.name) == ["eiffel tower"])
        #expect(diff.regressions.first?.before.decision.format == .image)
        #expect(diff.regressions.first?.after.decision.format == .webResults)
        #expect(diff.fixes.map(\.name) == ["reddit"])
        #expect(diff.added == ["new one"])
        #expect(diff.dropped == ["old one"])
    }

    @Test func anUncachedSideIsNeitherARegressionNorAFix() {
        let baseline = [result("news", expected: .webResults, got: .webResults)]
        let current = [result("news", expected: .webResults, got: .narrative, status: .uncached)]
        #expect(EvalDiff.compare(baseline: baseline, current: current) == EvalDiff())
        #expect(EvalDiff.compare(baseline: current, current: [result("news", expected: .webResults, got: .narrative)]) == EvalDiff())
    }
}
