import Foundation
import Testing
@testable import Evals
@testable import Engine

/// The stress run: drawing from the pool, routing with no labels, and the
/// order of the triage list. No network: the one routed run is answered
/// from a cache written by the test.
@Suite struct EvalSampleTests {
    private static let pool = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EvalSampleTests.swift → EvalsTests/
        .deletingLastPathComponent()   // → Tests/
        .deletingLastPathComponent()   // → Routing/
        .appending(path: "Evals/pool.txt")

    private func row(_ query: String, _ decision: Pick, floor: Double = 0.5, recency: Double = 0.5) -> TriageRow {
        EvalSample.row(EvalResult(EvalSample.evalCase(for: query), decision: decision, cached: true), floor: floor, recencyThreshold: recency)
    }

    // MARK: The pool

    @Test func thePoolSkipsCommentsAndBlanksAndKeepsARepeatOnce() {
        let text = """
        # web results
        news

          capital of peru
        news
        # a comment, not a query
        go to youtube
        """
        #expect(QueryPool.parse(Data(text.utf8)) == ["news", "capital of peru", "go to youtube"])
    }

    @Test func aDeviceLogGivesItsQueriesOnceEach() throws {
        let records = [
            DecisionRecord(timestamp: Date(timeIntervalSince1970: 1_792_600_000), query: "news", decision: Pick(instinct: .webResults, source: .jev)),
            DecisionRecord(timestamp: Date(timeIntervalSince1970: 1_792_600_100), query: "capital of peru", decision: Pick(instinct: .oneLine, source: .jev)),
            DecisionRecord(timestamp: Date(timeIntervalSince1970: 1_792_600_200), query: "news", decision: Pick(instinct: .webResults, source: .jev)),
        ]
        var data = Data()
        for record in records {
            data.append(try DecisionRecord.encoder.encode(record))
            data.append(UInt8(ascii: "\n"))
        }
        #expect(try QueryPool.parseLog(data) == ["news", "capital of peru"])
    }

    @Test func theCheckedInPoolIsLargeVariedAndRoutesOffline() throws {
        let queries = QueryPool.parse(try Data(contentsOf: Self.pool))
        #expect(queries.count >= 300)
        #expect(Set(queries).count == queries.count, "parse keeps each query once")
        #expect(queries.contains { $0.hasSuffix("please") || $0.hasSuffix("pls") }, "trailers")
        #expect(queries.contains { $0.lowercased().hasPrefix("can you") }, "leads")
        #expect(queries.contains { $0 != $0.lowercased() }, "casing")
        #expect(queries.contains { QueryParser.directURL(from: $0) != nil }, "an address or two")
    }

    // MARK: The draw

    @Test func aSeedDrawsTheSameDistinctQueriesEveryTime() {
        let pool = (0..<40).map { "query \($0)" }
        let first = EvalSample.sample(pool, count: 10, seed: 20_261_023)
        let second = EvalSample.sample(pool, count: 10, seed: 20_261_023)
        #expect(first == second)
        #expect(first.count == 10)
        #expect(Set(first).count == 10)
        #expect(Set(first).isSubset(of: pool))
        #expect(first != Array(pool.prefix(10)), "a draw, not the head of the file")
        #expect(EvalSample.sample(pool, count: 10, seed: 20_261_024) != first, "the next day draws differently")
    }

    @Test func aCountPastThePoolIsTheWholePoolShuffled() {
        let pool = (0..<7).map { "query \($0)" }
        let all = EvalSample.sample(pool, count: 50, seed: 1)
        #expect(all.count == 7)
        #expect(Set(all) == Set(pool))
        #expect(EvalSample.sample(pool, count: 0, seed: 1).isEmpty)
    }

    @Test func theSeedIsTheDay() {
        let zone = TimeZone(identifier: "America/Chicago")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 7, minute: 30))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23, minute: 50))!
        #expect(EvalSample.seed(for: morning, zone: zone) == 20_261_023)
        #expect(EvalSample.seed(for: evening, zone: zone) == 20_261_023, "the same day, the same draw")
        #expect(EvalSample.seed(for: evening.addingTimeInterval(3600), zone: zone) == 20_261_024)
    }

    // MARK: Doubts

    @Test func aPassJustOverTheFloorIsNearIt() throws {
        let near = row("reddit", try decision(choice: "site", confidence: 0.56, probabilities: ["site": 0.6, "web_results": 0.35, "narrative": 0.05], recency: 0.1))
        #expect(near.doubts == [.nearFloor(by: 0.56 - 0.5)])
        #expect(near.runnerUp == TriageRow.RunnerUp(format: "web_results", probability: 0.35))
        #expect(near.isDoubtful)

        let sure = row("capital of peru", try decision(choice: "one_line", confidence: 0.92, probabilities: ["one_line": 0.93, "web_results": 0.07], recency: 0.1))
        #expect(sure.doubts.isEmpty)
        #expect(!sure.isDoubtful)
        #expect(sure.margin == nil)
    }

    @Test func aGateThatFiredIsADoubtByItsMargin() throws {
        let confidence = row("eiffel tower", try decision(choice: "image", confidence: 0.42, probabilities: ["image": 0.46, "web_results": 0.41, "narrative": 0.09], recency: 0.1))
        #expect(confidence.decision.source == .confidenceFallback)
        #expect(confidence.doubts.count == 1)
        if case let .confidenceFallback(by)? = confidence.doubts.first {
            #expect(abs(by - 0.08) < 0.0001)
        } else {
            Issue.record("expected a confidence fallback, got \(confidence.doubts)")
        }

        let recency = row("who won the super bowl", try decision(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.9, "web_results": 0.1], recency: 0.62))
        #expect(recency.decision.source == .jev, "the pick stands; the answer instinct shows web results")
        #expect(recency.doubts.count == 1)
        if case let .recent(by)? = recency.doubts.first {
            #expect(abs(by - 0.12) < 0.0001)
        } else {
            Issue.record("expected a recent doubt, got \(recency.doubts)")
        }
    }

    @Test func recencyNearTheThresholdOnlyMattersForAnAnsweredPick() throws {
        let answered = row("how old is the pope", try decision(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.9, "web_results": 0.1], recency: 0.44))
        #expect(answered.doubts.count == 1)
        if case let .nearRecency(by)? = answered.doubts.first {
            #expect(abs(by - 0.06) < 0.0001)
        } else {
            Issue.record("expected near recency, got \(answered.doubts)")
        }
        let page = row("tesla stock", try decision(choice: "stock", confidence: 0.9, probabilities: ["stock": 0.9, "web_results": 0.1], recency: 0.44))
        #expect(page.doubts.isEmpty, "a chart loads whatever the recency")
    }

    @Test func aFailureIsADoubtOfItsOwn() {
        let error = row("news", Pick(instinct: .webResults, source: .error("timeout")))
        #expect(error.doubts == [.error("timeout")])
        #expect(!error.isDoubtful)
        #expect(error.isUnrouted)

        let uncached = EvalSample.row(.uncached(EvalSample.evalCase(for: "news")), floor: 0.5, recencyThreshold: 0.5)
        #expect(uncached.doubts == [.uncached])
        #expect(uncached.isUnrouted)

        let address = row("apple.com", .directURL())
        #expect(address.doubts.isEmpty)
        #expect(address.runnerUp == nil)
    }

    // MARK: The order

    @Test func theMostDoubtfulComeFirst() throws {
        let sure = row("capital of peru", try decision(choice: "one_line", confidence: 0.92, probabilities: ["one_line": 0.93, "web_results": 0.07], recency: 0.1))
        let lessSure = row("quantum computing", try decision(choice: "web_results", confidence: 0.7, probabilities: ["web_results": 0.75, "narrative": 0.25], recency: 0.1))
        let nearFloor = row("reddit", try decision(choice: "site", confidence: 0.56, probabilities: ["site": 0.6, "web_results": 0.35], recency: 0.1))
        let fellBack = row("eiffel tower", try decision(choice: "image", confidence: 0.42, probabilities: ["image": 0.46, "web_results": 0.41], recency: 0.1))
        let nearRecency = row("how old is the pope", try decision(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.9, "web_results": 0.1], recency: 0.47))
        let failed = row("news", Pick(instinct: .webResults, source: .error("timeout")))
        let uncached = EvalSample.row(.uncached(EvalSample.evalCase(for: "black friday tv deals")), floor: 0.5, recencyThreshold: 0.5)
        let address = row("apple.com", .directURL())

        let sorted = EvalSample.sorted([sure, address, uncached, lessSure, nearFloor, failed, fellBack, nearRecency])
        #expect(sorted.map(\.query) == [
            "how old is the pope",         // 0.03 from the recency threshold
            "reddit",                      // 0.06 over the floor
            "eiffel tower",                // 0.08 under the floor
            "news",                        // an error
            "black friday tv deals",       // not cached
            "quantum computing",           // sure, less
            "capital of peru",             // sure, more
            "apple.com",                   // an address: nothing to doubt
        ])
    }

    @Test func tiesKeepTheQueryOrder() throws {
        let first = row("first", try decision(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1))
        let second = row("second", try decision(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1))
        #expect(EvalSample.sorted([second, first]).map(\.query) == ["second", "first"])
    }

    // MARK: The text

    @Test func eachRowReadsAsWhatWasDoneWhyToDoubtItAndALineToPaste() throws {
        let rows = EvalSample.sorted([
            row("capital of peru", try decision(choice: "one_line", confidence: 0.92, probabilities: ["one_line": 0.93, "web_results": 0.07], recency: 0.1)),
            row("eiffel tower", try decision(choice: "image", confidence: 0.42, probabilities: ["image": 0.46, "web_results": 0.41, "narrative": 0.09], recency: 0.1)),
            row("who won the super bowl", try decision(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.9, "web_results": 0.1], recency: 0.62)),
            EvalSample.row(.uncached(EvalSample.evalCase(for: "news")), floor: 0.5, recencyThreshold: 0.5),
            row("apple.com", .directURL()),
        ])
        let text = EvalSample.text(rows: rows, poolSize: 312, source: "pool.txt", seed: 20_261_023, floor: 0.5, recencyThreshold: 0.5, model: "jev-1.13.0")
        #expect(text.hasPrefix("sample pool.txt: 5 of 312 queries, seed 20261023, 2 doubtful (floor 0.5, recency 0.5, jev-1.13.0; 1 address, 3 from cache, 0 asked Jev, 1 not cached)\n"))
        #expect(text.contains("""
        doubtful (2):
          "eiffel tower"
              acted web_results (confidenceFallback), picked image, confidence 0.42, recency 0.10, runner-up web_results .41
              confidence 0.08 under the floor 0.5: planned   image .46  web_results .41  narrative .09
              {"query": "eiffel tower", "instinct": "planned"}
          "who won the super bowl"
              acted one_line (jev), confidence 0.90, recency 0.62, runner-up web_results .10
              recency 0.12 over the threshold 0.5: the instinct shows web results   one_line .90  web_results .10
              {"query": "who won the super bowl", "instinct": "one_line"}
        """))
        #expect(text.contains("""
        not routed (1):
          "news"
              not routed: not cached (set TYPESAFE_API_KEY to ask Jev)

        """), "no pick, so no golden line")
        #expect(!text.contains("{\"query\": \"news\""))
        #expect(text.contains("""
        sure (2):
          "capital of peru"
              acted one_line (jev), confidence 0.92, recency 0.10, runner-up web_results .07
              confidence 0.92 ≥ 0.5, recency 0.10 < 0.5   one_line .93  web_results .07
              {"query": "capital of peru", "instinct": "one_line"}
          "apple.com"
              acted web_results (directURL)
              address
              {"query": "apple.com", "instinct": "web_results"}
        """))
    }

    @Test func theGoldenLineEscapesTheQuery() throws {
        let line = EvalSample.goldenLine(row("what's a \"noul\"?", try decision(choice: "narrative", confidence: 0.9, probabilities: ["narrative": 0.9], recency: 0.1)))
        #expect(line == "{\"query\": \"what's a \\\"noul\\\"?\", \"instinct\": \"narrative\"}")
        let parsed = try EvalSet.parse(Data(line.utf8))
        #expect(parsed == [EvalCase(query: "what's a \"noul\"?", instinct: .narrative)], "the line is a golden-set case as printed")
    }

    @Test func theRowNamesThePickAndItsNumbers() throws {
        let image = row("what does a capybara look like", try decision(choice: "image", confidence: 0.9, probabilities: ["image": 0.9, "web_results": 0.1], recency: 0.1))
        #expect(EvalSample.describe(image, floor: 0.5, recencyThreshold: 0.5).acted == "acted image (jev), confidence 0.90, recency 0.10, runner-up web_results .10")
        let address = row("apple.com", .directURL())
        #expect(EvalSample.describe(address, floor: 0.5, recencyThreshold: 0.5).acted == "acted web_results (directURL)")
    }

    // MARK: The run

    @Test func aRunRoutesUnlabelledQueriesFromTheCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JevCache(directory: directory)
        let locale = Locale(identifier: "en_US")
        let peru = EngineRequest.request(for: "capital of peru", locale: locale)
        try cache.store(key: try JevCache.key(for: peru), request: peru, response: Data(jevResponse(choice: "one_line", confidence: 0.92, probabilities: ["one_line": 0.93, "web_results": 0.07], recency: 0.1).utf8), latencyMs: 120)
        let eiffel = EngineRequest.request(for: "eiffel tower", locale: locale)
        try cache.store(key: try JevCache.key(for: eiffel), request: eiffel, response: Data(jevResponse(choice: "image", confidence: 0.42, probabilities: ["image": 0.46, "web_results": 0.41, "narrative": 0.09], recency: 0.1).utf8), latencyMs: 130)

        let runner = EvalRunner(client: nil, cache: cache, locale: locale, floor: 0.5)
        let rows = await EvalSample.run(["capital of peru", "what time is it in tokyo", "news", "eiffel tower", "apple.com"], runner: runner)
        #expect(rows.map(\.query) == ["eiffel tower", "what time is it in tokyo", "news", "capital of peru", "apple.com"])
        #expect(rows.map(\.result.cached) == [true, false, false, true, false])
        #expect(rows[0].decision.source == .confidenceFallback)
        #expect(rows[1].result.status == .uncached, "a time question asks Jev like any other")
        #expect(rows[2].result.status == .uncached)
        #expect(rows[3].decision.instinct == .oneLine)
        #expect(rows[4].decision.source == .directURL)
    }
}
