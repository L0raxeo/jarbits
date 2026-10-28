import Foundation
import Testing
@testable import Evals
@testable import Engine

/// These share one `URLProtocol` handler, so they run one at a time.
@Suite(.serialized) struct EvalRunnerTests {
    private let peru = EvalCase(query: "capital of peru", instinct: .oneLine, source: "jev")

    private func runner(client: JevClient?, directory: URL, floor: Double = EngineRequest.confidenceFloor) -> EvalRunner {
        EvalRunner(client: client, cache: JevCache(directory: directory), floor: floor)
    }

    @Test func theFirstRunAsksOnceAndTheSecondReadsTheCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MockJevTransport.client(status: 200, body: jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.92, "web_results": 0.08], recency: 0.1))

        let first = await runner(client: client, directory: directory).run(peru)
        #expect(MockJevTransport.requests.count == 1)
        #expect(first.status == .pass)
        #expect(!first.cached)
        #expect(first.decision.instinct == .oneLine)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).count == 1)

        MockJevTransport.requests = []
        let second = await runner(client: client, directory: directory).run(peru)
        #expect(MockJevTransport.requests.isEmpty)
        #expect(second.cached)
        #expect(second.status == .pass)
        #expect(second.decision.probabilities == first.decision.probabilities)
    }

    @Test func aSweepReDecidesTheCacheWithoutAClient() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A page in the running, so a raised floor falls back to web rather
        // than being read as a split between the two answers.
        let client = MockJevTransport.client(status: 200, body: jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.55, "web_results": 0.45]))
        _ = await runner(client: client, directory: directory).run(peru)
        MockJevTransport.requests = []

        let swept = await runner(client: nil, directory: directory, floor: 0.95).run(peru)
        #expect(MockJevTransport.requests.isEmpty)
        #expect(swept.cached)
        #expect(swept.decision.source == .confidenceFallback)
        #expect(swept.status == .fail)
        #expect(swept.failures == ["instinct: expected one_line, got the planner (confidenceFallback)", "source: expected jev, got confidenceFallback"])
    }

    @Test func anAddressNeverAsksJev() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MockJevTransport.client(status: 200, body: "{}")
        let results = await runner(client: client, directory: directory).run([
            EvalCase(query: "apple.com", instinct: .webResults, source: "directURL"),
        ])
        #expect(MockJevTransport.requests.isEmpty)
        #expect(results.map(\.status) == [.pass])
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }

    @Test func noClientAndNoCacheIsUncached() async {
        let directory = temporaryDirectory()
        let result = await runner(client: nil, directory: directory).run(peru)
        #expect(result.status == .uncached)
        #expect(!result.cached)
    }

    @Test func aFailedRequestIsNotCached() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let failing = MockJevTransport.client(status: 500, body: "boom")
        let failed = await runner(client: failing, directory: directory).run(peru)
        #expect(failed.status == .fail)
        #expect(failed.failures == ["error: http 500: boom"])
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))

        let working = MockJevTransport.client(status: 200, body: jevResponse(choice: "one_line", confidence: 0.9, probabilities: ["one_line": 0.9]))
        let retried = await runner(client: working, directory: directory).run(peru)
        #expect(MockJevTransport.requests.count == 1)
        #expect(retried.status == .pass)
    }

    @Test func theOpenedSiteReachesJevAndTheRejectionIsLogged() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MockJevTransport.client(status: 200, body: jevResponse(choice: "site", confidence: 0.95, probabilities: ["site": 0.95, "web_results": 0.05], recency: 0.1, rejects: 0.93))
        let evalCase = EvalCase(query: "no not this one", opened: OpenedSite(name: "zillow", host: "www.zillow.com"), instinct: .site, source: "jev")
        let result = await runner(client: client, directory: directory).run(evalCase)
        #expect(result.status == .pass)
        #expect(result.decision.rejectsSite)
        let body = MockJevTransport.requests.first?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(body.contains("\"opened_site_name\":\"zillow\""), "the opened site reaches Jev")
    }
}
