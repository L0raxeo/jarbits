import Foundation
import Routing
import Testing
@testable import Answers

@Suite struct AnswersReportTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AnswersReportTests.swift → AnswersTests/
        .deletingLastPathComponent()   // → Tests/
        .deletingLastPathComponent()   // → Routing/
        .deletingLastPathComponent()   // → Packages/
        .deletingLastPathComponent()   // → repo root

    @Test func reportQuotesThePromptsTheAppSends() {
        let markdown = AnswersReport.markdown()
        #expect(markdown.contains(AnswerPrompt.system(for: .narrative)))
        #expect(markdown.contains(AnswerPrompt.system(for: .oneLine)))
        #expect(markdown.contains(AnswerPrompt.input(query: "<query>", context: .example)))
        #expect(markdown.contains(GeminiClient.defaultModel))
        #expect(markdown.contains("### `narrative` — system instruction, max \(AnswerPrompt.maxOutputTokens(for: .narrative)) output tokens"))
        #expect(markdown.contains("`user_input`") && markdown.contains("`model_output`"), "the continued-narrative shape is documented")
        #expect(markdown.contains("Every earlier turn is sent"))
        #expect(markdown.contains("### Input with earlier exchanges"))
        #expect(markdown.contains("- Searched \"<term searched>\"\n- Read \"<page title>\" (<host>)"), "the block is rendered from the same code")
        #expect(markdown.contains("### Input with facts"))
        #expect(markdown.contains("- <fact>\n- <fact>"))
        #expect(markdown.contains(ValueExtractor.factSystem))
        #expect(markdown.contains("### Values read by Gemini"))
        #expect(markdown.contains(ValueExtractor.system))
        #expect(markdown.contains("Earlier: Searched \"<term searched>\"\nRequest: <query>"))
        #expect(markdown.contains("\"required\":[\"temperature\"]"))
        #expect(markdown.contains("`extraction.outcome = extracted`"))
    }

    /// The Gemini half must be in the file; `ImagesTests` checks the whole file.
    @Test func committedRoutingFileHasTheGeminiPrompts() throws {
        let committed = try String(contentsOf: Self.repoRoot.appending(path: "ENGINE.md"), encoding: .utf8)
        #expect(committed.contains(AnswersReport.markdown()), "ENGINE.md is stale; run: \(EngineReport.regenerateCommand)")
    }

    @Test func oldLogLinesWithoutAnswersStillDecode() throws {
        let line = #"{"timestamp":"2026-10-21T10:00:00Z","query":"nasdaq","decision":{"instinct":"stock","probabilities":{},"source":{"jev":{}}}}"#
        let record = try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(line.utf8))
        #expect(record.answer == nil)
        #expect(record.decision.instinct == .stock)
    }

    @Test func decisionsReportSummarisesAnswers() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let decision = Pick(instinct: .oneLine, suggested: .oneLine, confidence: 0.9, probabilities: ["one_line": 0.9], model: "jev-1.13.0", latencyMs: 200, inputTokens: 500, source: .jev)
        let records = [
            DecisionRecord(timestamp: now, query: "time in lima", decision: decision, answer: AnswerSummary(
                model: GeminiClient.defaultModel, format: .oneLine,
                usage: AnswerUsage(inputTokens: 400, outputTokens: 8, thoughtTokens: 2),
                firstTokenMs: 900, latencyMs: 1200, outcome: .completed)),
            DecisionRecord(timestamp: now, query: "will it rain today", decision: decision, answer: AnswerSummary(
                model: GeminiClient.defaultModel, format: .oneLine,
                usage: AnswerUsage(inputTokens: 380, outputTokens: 4, thoughtTokens: 1),
                firstTokenMs: 400, latencyMs: 500, outcome: .needsLiveData)),
            DecisionRecord(timestamp: now, query: "why is the sky blue", decision: decision, answer: AnswerSummary(
                model: GeminiClient.defaultModel, format: .narrative, latencyMs: 10_000, outcome: .fellBackToWeb("timeout"))),
        ]
        let lines = try records.map { String(decoding: try DecisionRecord.encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        let parsed = try DecisionsReport.parse(Data(lines.utf8))
        #expect(parsed == records)

        let markdown = DecisionsReport.markdown(records: parsed)
        #expect(markdown.contains("3 answered by Gemini, about $0.0002 in tokens."))
        #expect(markdown.contains("| `one_line` | 2 | 1 | 1 | 0 | 0 | 900 ms | 1200 ms | 7 |"), Comment(rawValue: markdown))
        #expect(markdown.contains("| `narrative` | 1 | 0 | 0 | 0 | 1 | – | 10000 ms | 0 |"))
        #expect(markdown.contains("Needed live data (shown web results): \"will it rain today\""))
        #expect(markdown.contains("- \"why is the sky blue\": fell back to web, timeout"))
    }
}
