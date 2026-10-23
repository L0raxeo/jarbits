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
            switch question {
            case let .choice(instructions, options):
                #expect(markdown.contains("### `\(id)` — type `choice`"))
                #expect(markdown.contains(instructions.replacingOccurrences(of: "\n", with: " ")))
                for option in options {
                    #expect(markdown.contains("| `\(option.name)` |"), "missing option \(option.name)")
                    #expect(markdown.contains(option.criterion.examples[0]))
                }
            case let .noul(instructions, criteria):
                #expect(markdown.contains("### `\(id)` — type `noul`"))
                #expect(markdown.contains(instructions.replacingOccurrences(of: "\n", with: " ")))
                if let criteria {
                    #expect(markdown.contains(criteria.yes))
                    #expect(markdown.contains(criteria.no))
                }
            }
        }
        #expect(markdown.contains("### `recent` — type `noul`"))
        #expect(markdown.contains(JevRouting.recencyCriteria.yes))
        #expect(markdown.contains("`recencyFallback`"))
        #expect(markdown.contains("`local(\"time\")`"))
        #expect(markdown.contains("\"\(TimeQuery.placeOpeners[0])\""))
        #expect(markdown.contains("\"\(TimeQuery.trailers[0])\""))
        #expect(!markdown.contains("**noul**: a yes/no"), "noul is in use now")
        #expect(markdown.contains(JevClient.defaultModel))
        #expect(markdown.contains("2500 ms"))
        #expect(markdown.contains(RoutingReport.regenerateCommand))
    }

    /// The Jev half must open the file; `AnswersReportTests` checks the whole file.
    @Test func committedRoutingFileStartsWithTheJevContract() throws {
        let committed = try String(contentsOf: Self.repoRoot.appending(path: "ROUTING.md"), encoding: .utf8)
        #expect(committed.hasPrefix(RoutingReport.markdown()), "ROUTING.md is stale; run: \(RoutingReport.regenerateCommand)")
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
            DecisionRecord(timestamp: now.addingTimeInterval(240), query: "is charlie kirk alive", decision: RouteDecision(
                format: .webResults, suggested: .oneLine, confidence: 0.9,
                probabilities: ["one_line": 0.92, "web_results": 0.05], model: "jev-1.13.0", latencyMs: 150, inputTokens: 1100, recency: 0.91, source: .recencyFallback)),
            DecisionRecord(timestamp: now.addingTimeInterval(300), query: "what time is it in tokyo", decision: .local("time", format: .oneLine)),
        ]
        let lines = try records.map { String(decoding: try DecisionRecord.encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        let parsed = try DecisionsReport.parse(Data(lines.utf8))
        #expect(parsed == records)

        let markdown = DecisionsReport.markdown(records: parsed)
        #expect(markdown.contains("6 queries: 3 asked Jev, 1 answered on the device, 1 addresses, 0 without a key, 1 errors, 1 sent to web for recency."))
        #expect(markdown.contains("- `time`: 1, most recent \"what time is it in tokyo\""))
        #expect(markdown.contains("| `stock` | 1 | 1 | 0 | 0 | 0.91 | \"nasdaq stock\" |"))
        #expect(markdown.contains("| `map` | 1 | 0 | 1 | 0 | 0.30 | \"coffee\" |"))
        #expect(markdown.contains("| `one_line` | 1 | 0 | 0 | 1 | 0.90 | \"is charlie kirk alive\" |"))
        #expect(markdown.contains("| \"is charlie kirk alive\" | `one_line` | 0.91 |"))
        #expect(markdown.contains("Recency (threshold 0.5): mean – for answers shown, 0.91 for queries sent to web."))
        #expect(!markdown.contains("| `narrative` |"), "formats never picked are left out")
        #expect(markdown.contains("- \"tesla\": timeout"))
        #expect(markdown.contains("| \"coffee\" | `map` | 0.30 | `web_results` 0.33 |"))
    }

    @Test func emptyLogReportsNothing() {
        #expect(DecisionsReport.markdown(records: []).contains("No records."))
    }
}
