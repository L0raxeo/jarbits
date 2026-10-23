import Answers
import Foundation
import Routing
import Testing
@testable import Images

/// These share one `URLProtocol` handler, so they run one at a time.
@Suite(.serialized) struct ImageSearchTests {
    @Test func findsTheFlagSkipsTheDisambiguationAndKeepsDominicaAsAnAlternate() async throws {
        let search = MockWikipediaTransport.search(search: flagSearch, summaries: flagSummaries)
        let results = try await search.find("dominican flag")

        #expect(results.map(\.title) == ["Flag of the Dominican Republic", "Flag of Dominica"])
        let flag = try #require(results.first)
        #expect(flag.key == "Flag_of_the_Dominican_Republic")
        #expect(flag.description == nil, "an empty description is dropped")
        #expect(flag.imageURL.absoluteString.hasSuffix("960px-Flag_of_the_Dominican_Republic.svg.png"))
        #expect(flag.width == 900 && flag.height == 600)
        #expect(flag.pageURL.absoluteString == "https://en.wikipedia.org/wiki/Flag_of_the_Dominican_Republic")
        #expect(results[1].description == "National flag")

        let searchRequest = try #require(MockWikipediaTransport.requests.first)
        #expect(searchRequest.url?.path == "/w/rest.php/v1/search/page")
        #expect(searchRequest.url?.query?.contains("q=dominican%20flag") == true)
        #expect(searchRequest.url?.query?.contains("limit=5") == true)
        #expect(searchRequest.value(forHTTPHeaderField: "User-Agent") == ImageSearch.defaultUserAgent)
        // The list page had no thumbnail, so only three summaries were fetched.
        #expect(MockWikipediaTransport.requests.count == 4)
    }

    @Test func theAskingAroundTheSubjectStaysOutOfTheSearch() async throws {
        let search = MockWikipediaTransport.search(search: flagSearch, summaries: flagSummaries)
        let results = try await search.find("show me a picture of the dominican flag")
        #expect(results.first?.key == "Flag_of_the_Dominican_Republic")
        let searchRequest = try #require(MockWikipediaTransport.requests.first)
        #expect(searchRequest.url?.query?.contains("q=dominican%20flag") == true, "ImageQuery leaves the subject")
    }

    @Test func nothingWithAPictureIsNoImage() async {
        let search = MockWikipediaTransport.search(search: #"{"pages":[{"id":1,"key":"A","title":"A","excerpt":"","matched_title":null,"anchor":null,"description":"","thumbnail":null}]}"#, summaries: [:])
        await #expect(throws: ImageError.noImage) {
            try await search.find("x")
        }
    }

    @Test func onlyDisambiguationsIsNoImage() async {
        let search = MockWikipediaTransport.search(
            search: #"{"pages":[{"id":1,"key":"Dominican_flag","title":"Dominican flag","excerpt":"","matched_title":null,"anchor":null,"description":"","thumbnail":{"mimetype":"image/png","width":60,"height":40,"duration":null,"url":"//x"}}]}"#,
            summaries: flagSummaries
        )
        await #expect(throws: ImageError.noImage) {
            try await search.find("x")
        }
    }

    @Test func httpErrorSurfaces() async {
        MockWikipediaTransport.handler = { _ in (503, Data("busy".utf8)) }
        MockWikipediaTransport.requests = []
        let search = ImageSearch(session: MockWikipediaTransport.session())
        await #expect(throws: ImageError.http(status: 503, body: "busy")) {
            try await search.find("x")
        }
    }

    @Test func slowSearchTimesOut() async {
        MockWikipediaTransport.handler = { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return (200, Data(flagSearch.utf8))
        }
        MockWikipediaTransport.requests = []
        let search = ImageSearch(timeout: .milliseconds(50), session: MockWikipediaTransport.session())
        await #expect(throws: ImageError.timeout) {
            try await search.find("x")
        }
    }

    @Test func pictureBytesComeBackWithTheUserAgent() async throws {
        MockWikipediaTransport.handler = { _ in (200, Data([0x89, 0x50, 0x4E, 0x47])) }
        MockWikipediaTransport.requests = []
        let search = ImageSearch(session: MockWikipediaTransport.session())
        let url = URL(string: "https://thumb.wikimedia.org/x.png")!
        let data = try await search.data(for: url)
        #expect(data.count == 4)
        // Found by URL: a request from an earlier, timed-out test can still land in the list.
        let request = try #require(MockWikipediaTransport.requests.first { $0.url == url })
        #expect(request.value(forHTTPHeaderField: "User-Agent") == ImageSearch.defaultUserAgent)
        #expect(request.value(forHTTPHeaderField: "Accept") == "image/*")
    }
}

@Suite struct ImagesReportTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ImageSearchTests.swift → ImagesTests/
        .deletingLastPathComponent()   // → Tests/
        .deletingLastPathComponent()   // → Routing/
        .deletingLastPathComponent()   // → Packages/
        .deletingLastPathComponent()   // → repo root

    @Test func reportNamesBothEndpoints() {
        let markdown = ImagesReport.markdown()
        #expect(markdown.contains("/w/rest.php/v1/search/page"))
        #expect(markdown.contains("/api/rest_v1/page/summary/"))
        #expect(markdown.contains(ImageSearch.defaultUserAgent))
        #expect(markdown.contains("`fellBackToWeb(reason)`"))
    }

    /// `ROUTING.md` opens with these three parts: the Jev contract, the
    /// Gemini prompts, the Wikipedia steps; `SitesReportTests` checks the whole file.
    @Test func committedRoutingFileIsCurrent() throws {
        let committed = try String(contentsOf: Self.repoRoot.appending(path: "ROUTING.md"), encoding: .utf8)
        let expected = RoutingReport.markdown() + "\n" + AnswersReport.markdown() + "\n" + ImagesReport.markdown()
        #expect(committed.hasPrefix(expected), "ROUTING.md is stale; run: \(RoutingReport.regenerateCommand)")
    }

    @Test func imageFormatIsBuiltAndComesAfterTheOlderOnes() {
        #expect(ResponseFormat.image.stage == .built)
        #expect(ResponseFormat.allCases.suffix(2) == [.image, .site], "appended in order, so Jev's leanings do not shift")
        #expect(!ResponseFormat.image.isAnswered)
    }

    @Test func decisionsReportSummarisesImages() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let decision = RouteDecision(format: .image, suggested: .image, confidence: 0.9, probabilities: ["image": 0.9], model: "jev-1.13.0", latencyMs: 150, inputTokens: 1200, source: .jev)
        let records = [
            DecisionRecord(timestamp: now, query: "dominican flag", decision: decision,
                           image: ImageSummary(article: "Flag of the Dominican Republic", candidates: 2, latencyMs: 700, outcome: .shown(alternates: 1))),
            DecisionRecord(timestamp: now, query: "eiffel tower", decision: decision,
                           image: ImageSummary(article: "Eiffel Tower", candidates: 1, latencyMs: 500, outcome: .shown(alternates: 0))),
            DecisionRecord(timestamp: now, query: "xyzzy logo", decision: decision,
                           image: ImageSummary(candidates: 0, latencyMs: 300, outcome: .fellBackToWeb("no image"))),
        ]
        let lines = try records.map { String(decoding: try DecisionRecord.encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        let parsed = try DecisionsReport.parse(Data(lines.utf8))
        #expect(parsed == records)

        let markdown = DecisionsReport.markdown(records: parsed)
        #expect(markdown.contains("3 image queries: 2 shown (1 with alternates), 1 fell back to web. Median latency 500 ms."), Comment(rawValue: markdown))
        #expect(markdown.contains("- \"xyzzy logo\": no image"))
    }

    @Test func oldLogLinesWithoutImagesStillDecode() throws {
        let line = #"{"timestamp":"2026-10-21T10:00:00Z","query":"nasdaq","decision":{"format":"stock","probabilities":{},"source":{"jev":{}}}}"#
        let record = try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(line.utf8))
        #expect(record.image == nil)
    }
}
