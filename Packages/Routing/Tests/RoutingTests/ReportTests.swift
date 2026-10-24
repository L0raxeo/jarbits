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
        #expect(markdown.contains("### `continues` — type `noul`"))
        #expect(markdown.contains(JevRouting.continuesCriteria.yes))
        #expect(markdown.contains(JevRouting.followUpInstructions))
        #expect(markdown.contains("`conversation`"))
        #expect(markdown.contains("`continuation` (the pick is kept as `suggested`)"))
        #expect(markdown.contains("## When an answer is on screen"))
        #expect(markdown.contains("as one line when `one_line` was picked with confidence"))
        #expect(markdown.contains("## After routing: recall"))
        #expect(markdown.contains(RecallRouting.recallCriteria.yes))
        #expect(markdown.contains("web page from yesterday (m.youtube.com)"))
        #expect(markdown.contains("`recencyFallback`"))
        #expect(markdown.contains("`local(\"time\")`"))
        #expect(markdown.contains("\"\(TimeQuery.placeOpeners[0])\""))
        #expect(markdown.contains("\"\(TimeQuery.trailers[0])\""))
        #expect(markdown.contains("`local(\"site\")`"))
        #expect(markdown.contains("\"\(SiteQuery.openers[0])\""))
        #expect(markdown.contains("\"\(SiteQuery.trailers.last!)\""))
        #expect(markdown.contains("## Decided on the device"))
        #expect(markdown.contains("`local(\"search\")`"))
        #expect(markdown.contains("\"\(SearchQuery.openers[0])\""))
        #expect(markdown.contains("\"\(SearchQuery.brandOpener)\""))
        #expect(markdown.contains("\"\(SearchQuery.googleProducts[0])\""))
        #expect(markdown.contains("\"\(SearchQuery.trailers[0])\""))
        #expect(markdown.contains("\"\(SearchQuery.corrections[0])\""))
        #expect(markdown.contains("| A search verb and a term (see above) | Web results for the term | `local(\"search\")` |"))
        #expect(markdown.contains("### `rejects` — type `noul`"))
        #expect(markdown.contains(JevRouting.rejectsCriteria.yes))
        #expect(markdown.contains("`opened_site_name`"))
        #expect(markdown.contains("`rejection` (the pick is kept as `suggested`)"))
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
            DecisionRecord(timestamp: now.addingTimeInterval(330), query: "look up steve jobs", decision: .local("search", format: .webResults)),
            DecisionRecord(timestamp: now.addingTimeInterval(360), query: "can I use water", decision: RouteDecision(
                format: .narrative, suggested: .webResults, confidence: 0.3,
                probabilities: ["web_results": 0.4, "narrative": 0.35], model: "jev-1.13.0", latencyMs: 230, inputTokens: 900, continuation: 0.8, source: .continuation)),
            DecisionRecord(timestamp: now.addingTimeInterval(390), query: "and chile?", decision: RouteDecision(
                format: .oneLine, suggested: .oneLine, confidence: 0.9,
                probabilities: ["one_line": 0.92, "narrative": 0.05], model: "jev-1.13.0", latencyMs: 210, inputTokens: 900, continuation: 0.9, source: .continuation)),
            DecisionRecord(timestamp: now.addingTimeInterval(420), query: "pull up the videos from yesterday", decision: RouteDecision(
                format: .recall, suggested: .recall, confidence: 0.9,
                probabilities: ["recall": 0.9, "web_results": 0.1], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, source: .jev),
                recall: RecallSummary(matches: 1, picked: .page, shortlisted: 4, judged: 1, source: "jev", latencyMs: 310)),
            DecisionRecord(timestamp: now.addingTimeInterval(480), query: "open insta", decision: .local("site", format: .site),
                site: SiteSummary(name: "insta", outcome: "opened", host: "www.instagram.com")),
            DecisionRecord(timestamp: now.addingTimeInterval(540), query: "go to hacker news", decision: RouteDecision(
                format: .site, suggested: .site, confidence: 0.9,
                probabilities: ["site": 0.9, "web_results": 0.1], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, source: .jev),
                site: SiteSummary(name: "hacker news", outcome: "choices", candidates: 5, latencyMs: 640)),
            DecisionRecord(timestamp: now.addingTimeInterval(600), query: "no not this one", decision: RouteDecision(
                format: .site, suggested: .narrative, confidence: 0.2,
                probabilities: ["narrative": 0.3, "web_results": 0.25], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, rejection: 0.9, source: .rejection),
                site: SiteSummary(name: "hacker news", outcome: "rejected", candidates: 5, latencyMs: 600)),
            DecisionRecord(timestamp: now.addingTimeInterval(660), query: "pull up lobsters", decision: RouteDecision(
                format: .site, suggested: .site, confidence: 0.8,
                probabilities: ["site": 0.8, "web_results": 0.2], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, source: .jev),
                site: SiteSummary(name: "lobsters", outcome: "results", reason: "no key")),
        ]
        let lines = try records.map { String(decoding: try DecisionRecord.encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        let parsed = try DecisionsReport.parse(Data(lines.utf8))
        #expect(parsed == records)

        let markdown = DecisionsReport.markdown(records: parsed)
        #expect(markdown.contains("14 queries: 9 asked Jev, 3 decided on the device, 1 addresses, 0 without a key, 1 errors, 1 sent to web for recency."))
        #expect(markdown.contains("1 recalls: 1 opened one memory, 0 showed a picker, 0 matched nothing and went to web. Jev judged 1, median 310 ms; 0 fell back to word order."))
        #expect(markdown.contains("4 site requests: 1 opened a remembered site, 1 showed choices, 1 fell back to web results, 1 rejected the site on screen. Median search latency 640 ms."))
        #expect(markdown.contains("Fell back: \"lobsters\": no key"))
        #expect(markdown.contains("- `site`: 1, most recent \"open insta\""))
        let old = #"{"matches":2}"#
        #expect(try DecisionRecord.decoder.decode(RecallSummary.self, from: Data(old.utf8)).source == nil, "old recall lines decode")
        let oldRecord = #"{"timestamp":"2026-10-01T00:00:00Z","query":"x","decision":{"format":"web_results","probabilities":{},"source":{"noKey":{}}}}"#
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(oldRecord.utf8)).site == nil, "lines without a site summary decode")
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(oldRecord.utf8)).decision.recall == nil, "lines without a recall intent decode")
        #expect(markdown.contains("| `web_results` | 1 | 1 | 0 | 0 | 0.30 | \"can I use water\" |"), "a continuation counts as acted on")
        #expect(markdown.contains("Follow-ups over an answer: 2 asked, 2 continued it (1 as one line), 0 went to another card, mean continuation 0.85."))
        #expect(markdown.contains("## Decided on the device"))
        #expect(markdown.contains("- `time`: 1, most recent \"what time is it in tokyo\""))
        #expect(markdown.contains("- `search`: 1, most recent \"look up steve jobs\""))
        #expect(markdown.contains("| `stock` | 1 | 1 | 0 | 0 | 0.91 | \"nasdaq stock\" |"))
        #expect(markdown.contains("| `map` | 1 | 0 | 1 | 0 | 0.30 | \"coffee\" |"))
        #expect(markdown.contains("| `one_line` | 2 | 1 | 0 | 1 | 0.90 | \"and chile?\", \"is charlie kirk alive\" |"), "a one-line continuation counts as acted on")
        #expect(markdown.contains("| \"is charlie kirk alive\" | `one_line` | 0.91 |"))
        #expect(markdown.contains("Recency (threshold 0.5): mean – for answers shown, 0.91 for queries sent to web."))
        #expect(!markdown.contains("| `image` |"), "formats never picked are left out")
        #expect(markdown.contains("- \"tesla\": timeout"))
        #expect(markdown.contains("| \"coffee\" | `map` | 0.30 | `web_results` 0.33 |"))
    }

    @Test func emptyLogReportsNothing() {
        #expect(DecisionsReport.markdown(records: []).contains("No records."))
    }
}
