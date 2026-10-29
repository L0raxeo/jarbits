import Answers
import Foundation
import Engine
import Testing
@testable import Sites

/// These share one `URLProtocol` handler, so they run one at a time.
@Suite(.serialized) struct SiteSearchTests {
    @Test func findsTheSitesOnePerHostWithIcons() async throws {
        let search = MockBraveTransport.search(body: hackerNewsSearch)
        let found = try await search.find("hacker news")

        #expect(found.map(\.host) == ["news.ycombinator.com", "en.wikipedia.org", "x.com", "thehackernews.com", "hn.algolia.com"], "one per host, www. aside, five at most")
        let first = try #require(found.first)
        #expect(first.title == "Hacker News")
        #expect(first.url.absoluteString == "https://news.ycombinator.com/")
        #expect(first.description == "Hacker News new | past | comments")
        #expect(first.favicon?.absoluteString == "https://imgs.search.brave.com/hn.ico", "the result's own favicon")
        #expect(found[1].favicon?.absoluteString == "https://www.google.com/s2/favicons?sz=64&domain=en.wikipedia.org", "no favicon in the result: the public service")
        #expect(found[2].favicon?.absoluteString == "https://imgs.search.brave.com/x.png", "the profile image when there is no meta_url")
        #expect(found[2].description == nil, "an empty description is dropped")

        let request = try #require(MockBraveTransport.requests.first)
        #expect(request.url?.path == "/res/v1/web/search")
        #expect(request.url?.query?.contains("q=hacker%20news") == true)
        #expect(request.url?.query?.contains("count=\(SiteSearch.searchCount)") == true)
        #expect(request.url?.query?.contains("result_filter=web") == true)
        #expect(request.value(forHTTPHeaderField: "X-Subscription-Token") == "brave-test")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func noWebResultsIsNoResults() async {
        let search = MockBraveTransport.search(body: #"{"type":"search","query":{"original":"x"}}"#)
        await #expect(throws: SiteError.noResults) {
            try await search.find("x")
        }
        let empty = MockBraveTransport.search(body: #"{"type":"search","web":{"type":"search","results":[]}}"#)
        await #expect(throws: SiteError.noResults) {
            try await empty.find("x")
        }
    }

    @Test func httpErrorSurfaces() async {
        let search = MockBraveTransport.search(status: 401, body: "unauthorized")
        await #expect(throws: SiteError.http(status: 401, body: "unauthorized")) {
            try await search.find("x")
        }
    }

    @Test func badJSONIsADecodingError() async {
        let search = MockBraveTransport.search(body: "not json")
        do {
            _ = try await search.find("x")
            Issue.record("decoded garbage")
        } catch {
            if case .decoding = error {} else { Issue.record("\(error)") }
        }
    }

    @Test func slowSearchTimesOut() async {
        MockBraveTransport.handler = { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return (200, Data(hackerNewsSearch.utf8))
        }
        MockBraveTransport.requests = []
        let search = SiteSearch(apiKey: "brave-test", timeout: .milliseconds(50), session: MockBraveTransport.session())
        await #expect(throws: SiteError.timeout) {
            try await search.find("x")
        }
    }
}

@Suite struct SitesReportTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SiteSearchTests.swift → SitesTests/
        .deletingLastPathComponent()   // → Tests/
        .deletingLastPathComponent()   // → Routing/
        .deletingLastPathComponent()   // → Packages/
        .deletingLastPathComponent()   // → repo root

    /// `ENGINE.md` is all four parts: the Jev contract, the Gemini prompts, the Wikipedia steps, the site steps.
    @Test func committedRoutingFileIsCurrent() throws {
        let committed = try String(contentsOf: Self.repoRoot.appending(path: "ENGINE.md"), encoding: .utf8)
        let expected = EngineReport.markdown() + "\n" + AnswersReport.markdown() + "\n" + SitesReport.markdown()
        #expect(committed == expected, "ENGINE.md is stale; run: \(EngineReport.regenerateCommand)")
    }

    @Test func siteFormatIsBuiltAndLast() {
        #expect(Instinct.allCases.suffix(6) == [.site, .video, .remember, .forget, .time, .notebook], "appended in order; video, the fact instincts, time and the notebook came after")
        #expect(Instinct.site.outranksConversation)
        #expect(!Instinct.site.isAnswered)
    }

    @Test func reportNamesTheEndpointAndTheOutcomes() {
        let markdown = SitesReport.markdown()
        #expect(markdown.hasPrefix("## After routing: sites"))
        #expect(markdown.contains("res/v1/web/search"))
        #expect(markdown.contains("X-Subscription-Token"))
        #expect(markdown.contains("`rejected`"))
        #expect(markdown.contains("\(SiteBook.seed.count) seeded sites"))
    }
}
