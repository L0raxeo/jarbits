import Foundation
import Testing
@testable import Engine

@Suite struct ReportTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ReportTests.swift → EngineTests/
        .deletingLastPathComponent()   // → Tests/
        .deletingLastPathComponent()   // → Routing/
        .deletingLastPathComponent()   // → Packages/
        .deletingLastPathComponent()   // → repo root

    @Test func routingReportDescribesEveryQuestionAndOption() {
        let markdown = EngineReport.markdown()
        let request = EngineRequest.request(for: "x", locale: Locale(identifier: "en_US"))
        for (id, question) in request.questions {
            switch question {
            case let .choice(instructions, options):
                #expect(markdown.contains("### `\(id)` — type `choice`"))
                #expect(markdown.contains(instructions.replacingOccurrences(of: "\n", with: " ")))
                for option in options {
                    #expect(markdown.contains("| `\(option.name)` |"), "missing option \(option.name)")
                    if let example = option.criterion.examples.first { #expect(markdown.contains(example)) }
                }
            case let .noul(instructions, criteria):
                #expect(markdown.contains("### `\(id)` — type `noul`"))
                #expect(markdown.contains(instructions.replacingOccurrences(of: "\n", with: " ")))
                if let criteria {
                    #expect(markdown.contains(criteria.yes))
                    #expect(markdown.contains(criteria.no))
                }
            case let .score(instructions, levels):
                #expect(markdown.contains("### `\(id)` — type `score`"))
                #expect(markdown.contains(instructions.replacingOccurrences(of: "\n", with: " ")))
                for level in levels { #expect(markdown.contains(level)) }
            }
        }
        #expect(markdown.contains("### `recent` — type `noul`"))
        #expect(markdown.contains(EngineRequest.recencyCriteria.yes))
        #expect(markdown.contains("### `remember` — type `noul`"))
        #expect(markdown.contains(EngineRequest.rememberCriteria.no))
        #expect(markdown.contains("| `remember` picked |"))
        #expect(markdown.contains("| `forget` picked |"))
        #expect(markdown.contains("### `reasoning` — type `score`"))
        #expect(markdown.contains("| 2 | \(EngineRequest.reasoningLevels[2]) |"))
        #expect(markdown.contains("### `x0` — type `noul`"))
        #expect(markdown.contains(EngineRequest.relevanceCriteria.yes))
        #expect(markdown.contains(EngineRequest.contextInstructions()))
        #expect(markdown.contains("`exchanges`"))
        #expect(markdown.contains("| `jev` with `continues` |"))
        #expect(markdown.contains("## When earlier exchanges are in the state"))
        #expect(markdown.contains("| `jev` with `chain` above 0 |"))
        #expect(markdown.contains("| Address typed | That page | `directURL` |"))
        #expect(markdown.contains("| `time` picked |"))
        #expect(markdown.contains("see \"The reading beside Jev\""))
        #expect(markdown.contains("`reasoningWanted`"))
        #expect(markdown.contains("## After routing: recall"))
        #expect(markdown.contains(RecallRouting.recallCriteria.yes))
        #expect(markdown.contains("web page from yesterday (m.youtube.com)"))
        #expect(!markdown.contains("`recencyFallback`"), "no gate overrules a pick")
        #expect(!markdown.contains("`local(\"time\")`") && !markdown.contains("## Decided on the device") && !markdown.contains("## Grammars after the pick"), "no rule and no grammar decides a query")
        #expect(markdown.contains("| `narrative` or `one_line` picked, `recent` at or above 0.5 |"))
        #expect(markdown.contains("### `rejects` — type `noul`"))
        #expect(markdown.contains(EngineRequest.rejectsCriteria.yes))
        #expect(markdown.contains("`opened_site_name`"))
        #expect(markdown.contains("`jev`, with `rejection` on the line"))
        #expect(!markdown.contains("**noul**: a yes/no"), "noul is in use now")
        #expect(!markdown.contains("**score**"), "score is in use now")
        #expect(markdown.contains(JevClient.defaultModel))
        #expect(markdown.contains("20000 ms"))
        #expect(markdown.contains(EngineReport.regenerateCommand))
    }

    /// The Jev half must open the file; `AnswersReportTests` checks the whole file.
    @Test func committedRoutingFileStartsWithTheJevContract() throws {
        let committed = try String(contentsOf: Self.repoRoot.appending(path: "ENGINE.md"), encoding: .utf8)
        #expect(committed.hasPrefix(EngineReport.markdown()), "ENGINE.md is stale; run: \(EngineReport.regenerateCommand)")
    }

    @Test func decisionsReportSummarisesALog() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [
            DecisionRecord(timestamp: now, query: "nasdaq stock", decision: Pick(
                instinct: .stock, suggested: .stock, confidence: 0.91,
                probabilities: ["stock": 0.92, "web_results": 0.05], model: "jev-1.13.0", latencyMs: 210, inputTokens: 500, reasoning: 0.2, reasoningConfidence: 0.8, source: .jev)),
            DecisionRecord(timestamp: now.addingTimeInterval(60), query: "coffee", decision: Pick(
                instinct: .webResults, suggested: .map, confidence: 0.3,
                probabilities: ["map": 0.37, "web_results": 0.33], model: "jev-1.13.0", latencyMs: 190, inputTokens: 500, reasoning: 1.7, reasoningConfidence: 0.6, source: .confidenceFallback)),
            DecisionRecord(timestamp: now.addingTimeInterval(120), query: "apple.com", decision: .directURL()),
            DecisionRecord(timestamp: now.addingTimeInterval(180), query: "tesla", decision: Pick(
                instinct: .webResults, latencyMs: 2500, source: .error("timeout"))),
            DecisionRecord(timestamp: now.addingTimeInterval(240), query: "is charlie kirk alive", decision: Pick(
                instinct: .oneLine, suggested: .oneLine, confidence: 0.9,
                probabilities: ["one_line": 0.92, "web_results": 0.05], model: "jev-1.13.0", latencyMs: 150, inputTokens: 1100, recency: 0.91, source: .jev)),
            DecisionRecord(timestamp: now.addingTimeInterval(300), query: "what time is it in tokyo", decision: Pick(
                instinct: .time, suggested: .time, confidence: 0.95,
                probabilities: ["time": 0.96, "one_line": 0.03], model: "jev-1.13.0", latencyMs: 180, inputTokens: 500, source: .jev)),
            DecisionRecord(timestamp: now.addingTimeInterval(330), query: "look up steve jobs", decision: Pick(
                instinct: .webResults, suggested: .webResults, confidence: 0.9,
                probabilities: ["web_results": 0.9, "narrative": 0.05], model: "jev-1.13.0", latencyMs: 190, inputTokens: 500, source: .jev)),
            DecisionRecord(timestamp: now.addingTimeInterval(360), query: "can I use water", decision: Pick(
                instinct: .narrative, suggested: .narrative, confidence: 0.8,
                probabilities: ["narrative": 0.8, "web_results": 0.1], model: "jev-1.13.0", latencyMs: 230, inputTokens: 900, relevance: [0.8], chain: 1, continues: true, source: .jev)),
            DecisionRecord(timestamp: now.addingTimeInterval(390), query: "and chile?", decision: Pick(
                instinct: .oneLine, suggested: .oneLine, confidence: 0.9,
                probabilities: ["one_line": 0.92, "narrative": 0.05], model: "jev-1.13.0", latencyMs: 210, inputTokens: 900, relevance: [0.9], chain: 1, continues: true, source: .jev)),
            DecisionRecord(timestamp: now.addingTimeInterval(420), query: "pull up the videos from yesterday", decision: Pick(
                instinct: .recall, suggested: .recall, confidence: 0.9,
                probabilities: ["recall": 0.9, "web_results": 0.1], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, source: .jev),
                recall: RecallSummary(matches: 1, picked: .page, shortlisted: 4, judged: 1, source: "jev", latencyMs: 310)),
            DecisionRecord(timestamp: now.addingTimeInterval(480), query: "open insta", decision: Pick(
                instinct: .site, suggested: .site, confidence: 0.9,
                probabilities: ["site": 0.9, "web_results": 0.1], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, source: .jev),
                site: SiteSummary(name: "insta", outcome: "opened", host: "www.instagram.com")),
            DecisionRecord(timestamp: now.addingTimeInterval(540), query: "go to hacker news", decision: Pick(
                instinct: .site, suggested: .site, confidence: 0.9,
                probabilities: ["site": 0.9, "web_results": 0.1], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, source: .jev),
                site: SiteSummary(name: "hacker news", outcome: "choices", candidates: 5, latencyMs: 640)),
            DecisionRecord(timestamp: now.addingTimeInterval(600), query: "no not this one", decision: Pick(
                instinct: .site, suggested: .site, confidence: 0.7,
                probabilities: ["site": 0.75, "web_results": 0.2], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, rejection: 0.9, source: .jev),
                site: SiteSummary(name: "hacker news", outcome: "rejected", candidates: 5, latencyMs: 600)),
            DecisionRecord(timestamp: now.addingTimeInterval(660), query: "pull up lobsters", decision: Pick(
                instinct: .site, suggested: .site, confidence: 0.8,
                probabilities: ["site": 0.8, "web_results": 0.2], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, source: .jev),
                site: SiteSummary(name: "lobsters", outcome: "results", reason: "no key"),
                reading: ReadingSummary(original: "oh pull up lobsters", query: "pull up lobsters", model: "gemini-3.1-flash-lite", latencyMs: 700, usage: AnswerUsage(inputTokens: 120, outputTokens: 10, thoughtTokens: 0), outcome: .rewritten)),
            DecisionRecord(timestamp: now.addingTimeInterval(720), query: "videos of pele", decision: Pick(
                instinct: .video, suggested: .video, confidence: 0.9,
                probabilities: ["video": 0.9, "web_results": 0.1], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, source: .jev),
                extraction: ExtractionSummary(model: "gemini-3.1-flash-lite", latencyMs: 400, usage: AnswerUsage(inputTokens: 150, outputTokens: 8, thoughtTokens: 0), fields: ["count"], outcome: .extracted)),
            DecisionRecord(timestamp: now.addingTimeInterval(780), query: "remember that I'm vegetarian", decision: Pick(
                instinct: .remember, suggested: .remember, confidence: 0.9,
                probabilities: ["remember": 0.9, "recall": 0.1], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, remember: 0.95, source: .jev),
                fact: FactSummary(action: "remembered", source: .told, text: "I'm vegetarian", remember: 0.95)),
            DecisionRecord(timestamp: now.addingTimeInterval(840), query: "remember I'm vegetarian, then suggest dinner", decision: Pick(
                instinct: .narrative, suggested: .narrative, confidence: 0.6,
                probabilities: ["narrative": 0.6, "remember": 0.4], model: "jev-1.13.0", latencyMs: 210, inputTokens: 520, reasoning: 1.8, reasoningConfidence: 0.7, source: .jev),
                engine: EngineSummary(model: "gemini-3.8-flash", rounds: 2, steps: [
                    .init(name: "remember", arguments: ["query": "I'm vegetarian", "fact": "I'm vegetarian"], outcome: "ran", latencyMs: 15),
                    .init(name: "narrative", arguments: ["query": "suggest a vegetarian dinner"], outcome: "shown", latencyMs: 1200),
                ], usage: AnswerUsage(inputTokens: 6000, outputTokens: 120, thoughtTokens: 80), latencyMs: 4200, factsGiven: 1, memoriesGiven: 0, outcome: .completed)),
            DecisionRecord(timestamp: now.addingTimeInterval(900), query: "do the thing", decision: Pick(
                instinct: .webResults, suggested: .narrative, confidence: 0.3,
                probabilities: ["narrative": 0.3, "web_results": 0.3], model: "jev-1.13.0", latencyMs: 190, inputTokens: 400, reasoning: 1.1, reasoningConfidence: 0.5, source: .confidenceFallback),
                engine: EngineSummary(model: "gemini-3.8-flash", rounds: 1, steps: [], usage: AnswerUsage(inputTokens: 5000, outputTokens: 40, thoughtTokens: 20), latencyMs: 1500, factsGiven: 0, memoriesGiven: 2, outcome: .fellBackToWeb("round 1: no calls"))),
            DecisionRecord(timestamp: now.addingTimeInterval(845), query: "suggest a vegetarian dinner", decision: Pick(instinct: .narrative, suggested: nil, confidence: 1, source: .plan),
                answer: AnswerSummary(model: "gemini-3.1-flash-lite", format: .narrative, usage: AnswerUsage(inputTokens: 900, outputTokens: 180, thoughtTokens: 0), firstTokenMs: 500, latencyMs: 2000, outcome: .completed)),
            DecisionRecord(timestamp: now.addingTimeInterval(850), query: "my friend noah went vegan once", decision: Pick(instinct: .narrative, suggested: .narrative, confidence: 0.95, probabilities: ["narrative": 0.95], model: "jev-1.13.0", latencyMs: 180, inputTokens: 300, remember: 0.8, source: .jev),
                extraction: ExtractionSummary(model: "gemini-3.1-flash-lite", latencyMs: 900, usage: AnswerUsage(inputTokens: 600, outputTokens: 60, thoughtTokens: 0), fields: ["facts"], outcome: .extracted),
                fact: FactSummary(action: "read", source: .inferred, text: "Lorcan has a friend named Noah", remember: 0.8, latencyMs: 900, found: 2, restated: 0, replaced: 0)),
        ]
        let lines = try records.map { String(decoding: try DecisionRecord.encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        let parsed = try DecisionsReport.parse(Data(lines.utf8))
        #expect(parsed == records)

        let oldRecord = #"{"timestamp":"2026-10-01T00:00:00Z","query":"x","decision":{"instinct":"web_results","probabilities":{},"source":{"noKey":{}}}}"#
        let markdown = DecisionsReport.markdown(records: parsed)
        #expect(markdown.contains("20 queries: 17 asked Jev, 1 addresses, 0 without a key, 1 errors, 1 answers sent to web for recency, 1 steps of plans. 1 rewritten by the reading."))
        #expect(markdown.contains("## Readings"))
        #expect(markdown.contains("1 read beside Jev: 1 rewritten, 0 unchanged, 0 failed. Median latency 700 ms; about $0.0000 in tokens."))
        #expect(markdown.contains("Rewritten: \"oh pull up lobsters\" → \"pull up lobsters\""))
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(oldRecord.utf8)).reading == nil, "lines without a reading decode")
        let versionOne = #"{"timestamp":"2026-10-01T00:00:00Z","query":"what time is it","decision":{"instinct":"one_line","probabilities":{},"source":{"local":{"_0":"time"}}}}"#
        let lenient = DecisionsReport.parseLenient(Data((lines + versionOne + "\n").utf8))
        #expect(lenient.records == records && lenient.skipped == 1, "a version 1 line is skipped and counted")
        #expect(markdown.contains("## Reasoning"))
        #expect(markdown.contains("2 plans: 1 completed, 1 fell back to web, 0 declined, 0 over budget, 0 overtaken. Mean 1.5 rounds and 1.0 steps; median 4200 ms; about $0.0092 in tokens."))
        #expect(markdown.contains("Fell back: \"do the thing\": round 1: no calls"))
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(oldRecord.utf8)).engine == nil, "lines without a plan decode")
        #expect(markdown.contains("2 asked a model for a value: 2 read one, 0 came back empty, 0 failed. Median latency 900 ms."))
        #expect(markdown.contains("1 touched the facts: 1 remembered (1 told, 0 chosen, 0 inferred), 0 forgotten, 0 declined, 0 found nothing to keep or drop."))
        #expect(markdown.contains("1 read for facts beside the query: 2 new, 0 restated, 0 changed; 0 found nothing, 0 failed. Median latency 900 ms."))
        #expect(markdown.contains("Remember gate (threshold 0.5): mean 0.95 where a fact was kept, 0.88 over every query asked."))
        #expect(markdown.contains("Kept: \"I'm vegetarian\""))
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(oldRecord.utf8)).fact == nil, "lines without a fact decode")
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(oldRecord.utf8)).extraction == nil, "lines without an extraction decode")
        #expect(markdown.contains("1 recalls: 1 opened one memory, 0 showed a picker, 0 matched nothing and went to web. Jev judged 1, median 310 ms; 0 fell back to word order."))
        #expect(markdown.contains("4 site requests: 1 opened a remembered site, 1 showed choices, 1 fell back to web results, 1 rejected the site on screen. Median search latency 640 ms."))
        #expect(markdown.contains("Fell back: \"lobsters\": no key"))
        let old = #"{"matches":2}"#
        #expect(try DecisionRecord.decoder.decode(RecallSummary.self, from: Data(old.utf8)).source == nil, "old recall lines decode")
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(oldRecord.utf8)).site == nil, "lines without a site summary decode")
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(oldRecord.utf8)).decision.recall == nil, "lines without a recall intent decode")
        #expect(try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(oldRecord.utf8)).decision.chain == nil, "lines without a chain decode")
        #expect(markdown.contains("| `web_results` | 1 | 1 | 0 | 0 | 0.90 | \"look up steve jobs\" |"))
        #expect(markdown.contains("| `narrative` | 4 | 3 | 1 | 0 | 0.66 | \"do the thing\", \"my friend noah went vegan once\", \"remember I'm vegetarian, then suggest dinner\" |"), "a continuation counts as acted on")
        #expect(markdown.contains("| `time` | 1 | 1 | 0 | 0 | 0.95 | \"what time is it in tokyo\" |"))
        #expect(markdown.contains("Queries with earlier exchanges: 2 asked, 2 depended on the newest (mean chain 1.0), 2 continued an answer (1 as one line), 0 went to another card."))
        #expect(markdown.contains("Reasoning (0 direct, 2 several steps): mean score 1.20 over 4; 1 unsure picks leaned to several steps."))
        #expect(!markdown.contains("## Decided on the device"))
        #expect(markdown.contains("| `stock` | 1 | 1 | 0 | 0 | 0.91 | \"nasdaq stock\" |"))
        #expect(markdown.contains("| `map` | 1 | 0 | 1 | 0 | 0.30 | \"coffee\" |"))
        #expect(markdown.contains("| `one_line` | 2 | 1 | 0 | 1 | 0.90 | \"and chile?\", \"is charlie kirk alive\" |"), "a one-line continuation counts as acted on; a recent one is sent to web by its instinct")
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
