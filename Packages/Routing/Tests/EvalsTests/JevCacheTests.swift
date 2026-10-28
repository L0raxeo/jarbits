import CryptoKit
import Foundation
import Testing
@testable import Evals
@testable import Routing

@Suite struct JevCacheTests {
    private let locale = Locale(identifier: "en_US")

    @Test func theKeyIsTheHashOfTheBody() throws {
        let request = EngineRequest.request(for: "capital of peru", locale: locale)
        let expected = SHA256.hash(data: try request.jsonData()).map { String(format: "%02x", $0) }.joined()
        #expect(try JevCache.key(for: request) == expected)
        #expect(try JevCache.key(for: request) == JevCache.key(for: EngineRequest.request(for: "capital of peru", locale: locale)), "the same request is the same bytes")
    }

    @Test func whatJevSeesChangesTheKeyAndNothingElseDoes() throws {
        let plain = try JevCache.key(for: EngineRequest.request(for: "capital of peru", locale: locale))
        #expect(try JevCache.key(for: EngineRequest.request(for: "capital of peru", locale: locale, model: "jev-2.0.0")) != plain)
        #expect(try JevCache.key(for: EngineRequest.request(for: "capital of peru", locale: Locale(identifier: "en_GB"))) != plain)
        #expect(try JevCache.key(for: EngineRequest.request(for: "capital of peru", locale: locale, exchanges: [.answer(query: "q", text: "a")])) != plain)
        #expect(try JevCache.key(for: EngineRequest.request(for: "capital of peru", locale: locale, exchanges: [.search(query: "q", term: "t")])) != plain)
        #expect(try JevCache.key(for: EngineRequest.request(for: "capital of peru", locale: locale, opened: OpenedSite(name: "zillow", host: "www.zillow.com"))) != plain)
        #expect(try JevCache.key(for: EngineRequest.request(for: "Capital of Peru", locale: locale)) != plain, "the query as typed")
    }

    @Test func anEntryRoundTrips() throws {
        let cache = JevCache(directory: temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: cache.directory) }
        let request = EngineRequest.request(for: "capital of peru", locale: locale)
        let key = try JevCache.key(for: request)
        #expect(cache.entry(for: key) == nil)
        let body = Data(jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.9, "web_results": 0.1], recency: 0.1, reasoning: (score: 0.1, confidence: 0.9)).utf8)
        let date = Date(timeIntervalSince1970: 1_792_600_000)
        try cache.store(key: key, request: request, response: body, latencyMs: 163, date: date)

        let entry = try #require(cache.entry(for: key))
        #expect(entry.latencyMs == 163)
        #expect(entry.model == "jev-1.13.0")
        #expect(entry.query == "capital of peru")
        #expect(Int(entry.date.timeIntervalSince1970) == 1_792_600_000)
        #expect(entry.response == (try JSONDecoder().decode(SystemOneResponse.self, from: body)))
        if case let .score(answer)? = entry.response.answers["reasoning"] {
            #expect(answer.score == 0.1)
        } else {
            Issue.record("the score answer is kept")
        }
        let file = try String(contentsOf: cache.fileURL(for: key), encoding: .utf8)
        #expect(file.contains("\"query\":\"capital of peru\""), "greppable by the query")
    }

    @Test func aCorruptFileReadsAsNothing() throws {
        let cache = JevCache(directory: temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: cache.directory) }
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        try Data("{\"date\": 1".utf8).write(to: cache.fileURL(for: "abc"))
        #expect(cache.entry(for: "abc") == nil)
    }
}
