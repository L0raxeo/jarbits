import Foundation
import Testing
@testable import Routing

@Suite struct ReportTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ReportTests.swift → RoutingTests/
        .deletingLastPathComponent()   // → Tests/
        .deletingLastPathComponent()   // → Routing/
        .deletingLastPathComponent()   // → Packages/
        .deletingLastPathComponent()   // → repo root

    @Test func routingReportDescribesEveryQuestionAndOption() {
        let markdown = RoutingReport.markdown()
        let request = JevRouting.request(for: "x", locale: Locale(identifier: "en_US"))
        for (id, question) in request.questions {
            #expect(markdown.contains("### `\(id)` — type `choice`"))
            if case let .choice(instructions, options) = question {
                #expect(markdown.contains(instructions.replacingOccurrences(of: "\n", with: " ")))
                for option in options {
                    #expect(markdown.contains("| `\(option.name)` |"), "missing option \(option.name)")
                    #expect(markdown.contains(option.criterion.examples[0]))
                }
            }
        }
        #expect(markdown.contains(JevClient.defaultModel))
        #expect(markdown.contains("2500 ms"))
        #expect(markdown.contains(RoutingReport.regenerateCommand))
    }

    @Test func committedRoutingFileIsCurrent() throws {
        let committed = try String(contentsOf: Self.repoRoot.appending(path: "ROUTING.md"), encoding: .utf8)
        #expect(committed == RoutingReport.markdown(), "ROUTING.md is stale; run: \(RoutingReport.regenerateCommand)")
    }

    @Test func decisionsReportSummarisesALog() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [
            DecisionRecord(timestamp: now, query: "nasdaq stock", decision: RouteDecision(
                format: .stock, suggested: .stock, confidence: 0.91,
                probabilities: ["stock": 0.92, "web_results": 0.05], model: "jev-1.13.0", latencyMs: 210, inputTokens: 500, source: .jev)),
            DecisionRecord(timestamp: now.addingTimeInterval(60), query: "coffee", decision: RouteDecision(
                format: .webResults, suggested: .map, confidence: 0.3,
                probabilities: ["map": 0.37, "web_results": 0.33], model: "jev-1.13.0", latencyMs: 190, inputTokens: 500, source: .confidenceFallback)),
            DecisionRecord(timestamp: now.addingTimeInterval(120), query: "apple.com", decision: .directURL()),
            DecisionRecord(timestamp: now.addingTimeInterval(180), query: "tesla", decision: RouteDecision(
                format: .webResults, latencyMs: 2500, source: .error("timeout"))),
        ]
        let lines = try records.map { String(decoding: try DecisionRecord.encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        let parsed = try DecisionsReport.parse(Data(lines.utf8))
        #expect(parsed == records)

        let markdown = DecisionsReport.markdown(records: parsed)
        #expect(markdown.contains("4 queries: 2 asked Jev, 1 addresses, 0 without a key, 1 errors."))
        #expect(markdown.contains("| `stock` | 1 | 1 | 0 | 0.91 | \"nasdaq stock\" |"))
        #expect(markdown.contains("| `map` | 1 | 0 | 1 | 0.30 | \"coffee\" |"))
        #expect(!markdown.contains("| `one_line` |"), "formats never picked are left out")
        #expect(markdown.contains("- \"tesla\": timeout"))
        #expect(markdown.contains("| \"coffee\" | `map` | 0.30 | `web_results` 0.33 |"))
    }

    @Test func emptyLogReportsNothing() {
        #expect(DecisionsReport.markdown(records: []).contains("No records."))
    }
}
