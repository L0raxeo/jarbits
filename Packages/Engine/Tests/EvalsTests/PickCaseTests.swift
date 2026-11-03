import Foundation
import Testing
@testable import Evals
@testable import Engine

@Suite struct PickCaseTests {
    @Test func aLineParsesAndNamesItself() throws {
        let lines = """
        {"query": "what month do I graduate?", "needed": ["Lorcan is a junior at Lehigh University."], "helpful": ["Lorcan is studying computer science."], "note": "n"}
        {"query": "and what's she into", "exchanges": [{"query": "how old is my mom", "kind": "answer", "text": "50."}], "needed": ["Lorcan's mom Jasmine loves gardening."]}
        {"query": "capital of peru?", "needed": []}
        """
        let cases = try PickSet.parse(Data(lines.utf8))
        #expect(cases.map(\.name) == ["what month do I graduate?", "and what's she into after \"how old is my mom\"", "capital of peru?"])
        #expect(cases[0].helpful == ["Lorcan is studying computer science."])
        #expect(cases[1].exchanges?.first?.kind == .answer)
        #expect(throws: EvalSetError.self) { try PickSet.parse(Data("{\"query\": \"x\", \"needed\": []}\n{\"query\": \"x\", \"needed\": []}".utf8)) }
        #expect(throws: EvalSetError.self) { try PickSet.parse(Data("{\"query\": \"x\"}".utf8)) }
    }

    @Test func thePoolIsReadOnceAndTheSubsetsAreFixed() {
        let pool = PickPool.parse(Data("# a comment\nLorcan is left-handed.\n\nLorcan hates olives.\nLorcan is left-handed.\n".utf8))
        #expect(pool == ["Lorcan is left-handed.", "Lorcan hates olives."])
        let facts = PickPool.facts(pool: pool, adding: ["Lorcan hates olives.", "Lorcan supports Arsenal."])
        #expect(facts.map(\.text) == ["Lorcan is left-handed.", "Lorcan hates olives.", "Lorcan supports Arsenal."], "the pool in order, then what it lacks")
        #expect(facts.allSatisfy { $0.date == PickPool.factDate })
        let pickCase = PickCase(query: "which match should I watch", needed: ["Lorcan supports Arsenal."], helpful: ["Lorcan hates olives."])
        let big = PickPool.facts(pool: (0..<50).map { "Lorcan's friend number \($0) plays the cello." }, adding: pickCase.needed + (pickCase.helpful ?? []))
        let subset = PickPool.subset(for: pickCase, pool: big, size: 10)
        #expect(subset.count == 10)
        #expect(subset.contains(Fact.key("Lorcan supports Arsenal.")) && subset.contains(Fact.key("Lorcan hates olives.")), "the needed and helpful facts are always in")
        #expect(subset == PickPool.subset(for: pickCase, pool: big, size: 10), "the same draw every time")
        #expect(subset != PickPool.subset(for: pickCase, pool: big, size: 11), "a different size, a different draw")
        #expect(PickPool.subset(for: pickCase, pool: big, size: 1).count == 2, "never fewer than the needed and helpful")
        #expect(PickPool.subset(for: pickCase, pool: big, size: 1000).count == big.count)
    }

    @Test func aCaseIsMeasuredAtEverySizeFromOneSetOfScores() {
        let pool = (0..<30).map { "Lorcan's cousin number \($0) drives a Tesla." }
        let pickCase = PickCase(query: "what do I drive", needed: ["Lorcan drives a 2018 Honda Civic."], helpful: ["Lorcan's car insurance renews in June."])
        let facts = PickPool.facts(pool: pool, adding: pickCase.needed + (pickCase.helpful ?? []))
        let runner = PickRunner(client: nil, cache: JevCache(directory: temporaryDirectory()), sizes: [5, 32])
        let scores = facts.map { FactScore(fact: $0, score: $0.text.contains("Civic") ? 0.95 : $0.text.contains("insurance") ? 0.4 : $0.text.contains("number 3 ") ? 0.5 : 0.05) }
        let result = runner.measure(pickCase, scores: scores, cached: true, latencyMs: 300, requests: 1)
        #expect(result.status == .pass)
        #expect(result.lowestNeeded == 0.95)
        #expect(result.sizes.map(\.size) == [5, 32])
        let small = result.sizes[0]
        #expect(small.neededReached == 1 && small.neededTotal == 1 && small.helpfulReached == 1 && small.passed)
        let whole = result.sizes[1]
        #expect(whole.sent == 3 && whole.extras == 1, "the cousin number 3 passed the bar as an extra")
        let strict = PickRunner(client: nil, cache: JevCache(directory: temporaryDirectory()), threshold: 0.99, sizes: [32])
        let missed = strict.measure(pickCase, scores: scores, cached: true, latencyMs: 0, requests: 1)
        #expect(missed.status == .fail && missed.failures == ["at 32: missed \"Lorcan drives a 2018 Honda Civic.\" 0.95"])
        let trap = PickCase(query: "capital of peru?", needed: [])
        let none = runner.measure(trap, scores: scores, cached: true, latencyMs: 0, requests: 1)
        #expect(none.status == .pass && none.lowestNeeded == nil && none.sizes[1].extras == 3, "nothing needed: everything sent is an extra")
    }

    @Test func aRunReadsTheCacheAndReportsAndDiffs() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JevCache(directory: directory)
        let pool = ["Lorcan is a junior at Lehigh University.", "Lorcan hates cilantro."]
        let pickCase = PickCase(query: "what month do I graduate?", needed: [pool[0]])
        let runner = PickRunner(client: nil, cache: cache, sizes: [2])
        let uncached = await runner.run([pickCase], pool: pool)
        #expect(uncached.first?.status == .uncached)
        let facts = PickPool.facts(pool: pool, adding: pickCase.needed)
        let request = FactPicking.request(for: pickCase.query, facts: facts, locale: Locale(identifier: "en_US"), model: FactPicking.model)
        let response = """
        {"model": "jev-1.14.0", "answers": {"f0": {"type": "score", "score": 1.6, "confidence": 0.8, "probabilities": {"0": 0.1, "1": 0.2, "2": 0.7}}, "f1": {"type": "score", "score": 0.1, "confidence": 0.9, "probabilities": {"0": 0.9, "1": 0.1, "2": 0.0}}}, "usage": {"input_tokens": 10, "output_tokens": 1}}
        """
        try cache.store(key: try JevCache.key(for: request), request: request, response: Data(response.utf8), latencyMs: 250)
        let results = await runner.run([pickCase], pool: pool)
        let result = try #require(results.first)
        #expect(result.status == .pass && result.cached && result.latencyMs == 250 && result.requests == 1)
        #expect(result.sizes.first?.sent == 1)
        let text = PickReport.text(results: results, file: "picks.jsonl", pool: "picks-pool.txt", poolSize: 2, model: FactPicking.model, threshold: 0.3, limit: 30)
        #expect(text.contains("picks picks.jsonl: 1 cases over picks-pool.txt (2 facts), 1 passed, 0 failed (jev-1.14.0, bar 0.3, at most 30; 1 from cache, 0 asked Jev)"))
        #expect(text.contains("2     needed 1/1   whole 1/1   sent 1.0 / 1 / 1   extras 0.0"), Comment(rawValue: text))
        #expect(text.contains("lowest needed: 0.90 \"what month do I graduate?\""))
        var failed = result
        failed.status = .fail
        let diff = PickDiff.compare(baseline: results, current: [failed])
        #expect(diff.regressions == [result.name] && diff.fixes.isEmpty)
        #expect(PickDiff.compare(baseline: uncached, current: results) == PickDiff(), "a case not cached before is neither a regression nor a fix")
        #expect(PickReport.text(diff: diff, baseline: "before.jsonl").hasPrefix("against before.jsonl: 1 regression, 0 fixes, 0 new, 0 dropped\n  regressions: \"what month do I graduate?\""))
    }
}
