import Answers
import Foundation
import Engine
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

    @Test func theSubjectIsSearchedAsGiven() async throws {
        let search = MockWikipediaTransport.search(search: flagSearch, summaries: flagSummaries)
        let results = try await search.find("dominican flag")
        #expect(results.first?.key == "Flag_of_the_Dominican_Republic")
        let searchRequest = try #require(MockWikipediaTransport.requests.first)
        #expect(searchRequest.url?.query?.contains("q=dominican%20flag") == true, "the reading beside Jev gives the subject; nothing is stripped here")
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
        #expect(markdown.contains("/res/v1/images/search"))
        #expect(markdown.contains("safesearch=strict"))
        #expect(markdown.contains("`fellBackToWeb(reason)`"))
    }

    /// `ENGINE.md` opens with these three parts: the Jev contract, the
    /// Gemini prompts, the Wikipedia steps; `SitesReportTests` checks the whole file.
    @Test func committedRoutingFileIsCurrent() throws {
        let committed = try String(contentsOf: Self.repoRoot.appending(path: "ENGINE.md"), encoding: .utf8)
        let expected = EngineReport.markdown() + "\n" + AnswersReport.markdown() + "\n" + ImagesReport.markdown()
        #expect(committed.hasPrefix(expected), "ENGINE.md is stale; run: \(EngineReport.regenerateCommand)")
    }

    @Test func imageFormatIsBuiltAndComesAfterTheOlderOnes() {
        #expect(Instinct.allCases.suffix(6) == [.image, .site, .video, .remember, .forget, .time], "appended in order, so Jev's leanings do not shift")
        #expect(!Instinct.image.isAnswered)
    }

    @Test func decisionsReportSummarisesImages() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let decision = Pick(instinct: .image, suggested: .image, confidence: 0.9, probabilities: ["image": 0.9], model: "jev-1.13.0", latencyMs: 150, inputTokens: 1200, source: .jev)
        let records = [
            DecisionRecord(timestamp: now, query: "dominican flag", decision: decision,
                           image: ImageSummary(article: "Flag of the Dominican Republic", candidates: 2, latencyMs: 700, outcome: .shown(alternates: 1))),
            DecisionRecord(timestamp: now, query: "eiffel tower", decision: decision,
                           image: ImageSummary(article: "Eiffel Tower", candidates: 1, latencyMs: 500, outcome: .shown(alternates: 0))),
            DecisionRecord(timestamp: now, query: "xyzzy logo", decision: decision,
                           image: ImageSummary(candidates: 0, latencyMs: 300, outcome: .fellBackToWeb("Wikipedia: no image; Brave: no image"))),
            DecisionRecord(timestamp: now, query: "dyson pencilvac", decision: decision,
                           image: ImageSummary(article: "Dyson PencilVac", candidates: 2, latencyMs: 900, source: .brave, outcome: .shown(alternates: 1))),
        ]
        let lines = try records.map { String(decoding: try DecisionRecord.encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        let parsed = try DecisionsReport.parse(Data(lines.utf8))
        #expect(parsed == records)

        let markdown = DecisionsReport.markdown(records: parsed)
        #expect(markdown.contains("4 image queries: 3 shown (2 with alternates, 1 from Brave), 1 fell back to web. Median latency 700 ms."), Comment(rawValue: markdown))
        #expect(markdown.contains("- \"xyzzy logo\": Wikipedia: no image; Brave: no image"))
    }

    @Test func oldLogLinesWithoutImagesStillDecode() throws {
        let line = #"{"timestamp":"2026-10-21T10:00:00Z","query":"nasdaq","decision":{"instinct":"stock","probabilities":{},"source":{"jev":{}}}}"#
        let record = try DecisionRecord.decoder.decode(DecisionRecord.self, from: Data(line.utf8))
        #expect(record.image == nil)
    }
}

/// The Brave step on its own: the request, the parsing, the link label.
/// Nested under `ImageSearchTests` so the shared mock transports see one
/// test at a time across all three suites.
extension ImageSearchTests {
@Suite(.serialized) struct BraveImageSearchTests {
    @Test func requestCarriesTheTokenTheSubjectTheCountAndStrictSafeSearch() async throws {
        let search = MockBraveImageTransport.search(search: pencilVacSearch)
        _ = try await search.find("dyson pencilvac")
        let request = try #require(MockBraveImageTransport.requests.first)
        #expect(request.url?.host() == "api.search.brave.com")
        #expect(request.url?.path == "/res/v1/images/search")
        let query = try #require(request.url?.query)
        #expect(query.contains("q=dyson%20pencilvac"))
        #expect(query.contains("count=5"))
        #expect(query.contains("safesearch=strict"))
        #expect(request.value(forHTTPHeaderField: "X-Subscription-Token") == "brave-test")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func resultsKeepBravesOrderAndNeedAnOriginalImage() async throws {
        let search = MockBraveImageTransport.search(search: pencilVacSearch)
        let found = try await search.find("dyson pencilvac")
        #expect(found.map(\.imageURL.absoluteString) == [
            "https://cdn.theverge.com/pencilvac-hero.jpg",
            "https://dyson-h.assetsadobe2.com/is/image/content/dam/dyson/pencilvac.png",
            "https://s.yimg.com/pencilvac.jpg",
        ], "the result without properties.url is dropped")
        let first = try #require(found.first)
        #expect(first.source == .brave)
        #expect(first.title == "Dyson PencilVac review")
        #expect(first.description == "theverge.com", "the publisher stands where the article description did")
        #expect(first.width == 2000 && first.height == 1333)
        #expect(first.pageURL.absoluteString == "https://www.theverge.com/dyson-pencilvac-review")
        #expect(first.sourceName == "theverge.com", "the card's link is the host without www.")
        #expect(found[1].sourceName == "dyson.com")
        #expect(found[2].title == "engadget.com", "an empty title falls back to the publisher")
        #expect(found[2].width == 0 && found[2].height == 0, "a size Brave does not know is 0")
    }

    @Test func noResultsIsNoImage() async {
        let search = MockBraveImageTransport.search(search: #"{"type":"images","results":[]}"#)
        await #expect(throws: ImageError.noImage) {
            try await search.find("x")
        }
    }

    @Test func httpErrorSurfaces() async {
        let search = MockBraveImageTransport.search(status: 401, search: "unauthorized")
        await #expect(throws: ImageError.http(status: 401, body: "unauthorized")) {
            try await search.find("x")
        }
    }

    @Test func pictureBytesComeWithoutTheToken() async throws {
        let url = URL(string: "https://cdn.theverge.com/pencilvac-hero.jpg")!
        let search = MockBraveImageTransport.search(search: "{}", pictures: [url.absoluteString: pngMagic])
        let data = try await search.data(for: url)
        #expect(data == pngMagic)
        let request = try #require(MockBraveImageTransport.requests.first { $0.url == url })
        #expect(request.value(forHTTPHeaderField: "X-Subscription-Token") == nil, "the key stays with Brave")
        #expect(request.value(forHTTPHeaderField: "Accept") == "image/*")
    }
}

/// The two sources in order: Wikipedia, then Brave behind it.
@Suite(.serialized) struct ImageLookupTests {
    private func lookup(wikipedia: String, summaries: [String: String] = [:], brave: BraveImageSearch?) -> ImageLookup {
        ImageLookup(wikipedia: MockWikipediaTransport.search(search: wikipedia, summaries: summaries), brave: brave, budget: .seconds(2))
    }

    private var pencilVacPictures: [String: Data] {
        ["https://dyson-h.assetsadobe2.com/is/image/content/dam/dyson/pencilvac.png": pngMagic,
         "https://s.yimg.com/pencilvac.jpg": Data("<html>not a picture</html>".utf8)]
    }

    @Test func aWikipediaMissIsFilledByBrave() async throws {
        let brave = MockBraveImageTransport.search(search: pencilVacSearch, pictures: pencilVacPictures)
        let pick = try await lookup(wikipedia: noThumbnailSearch, brave: brave).find("dyson pencilvac", decodes: decodesPNG)

        #expect(pick.source == .brave)
        #expect(pick.data == pngMagic)
        // The Verge's picture 404s, so Dyson's own is the picture; Engadget's is the one alternate left.
        #expect(pick.results.map(\.sourceName) == ["dyson.com", "engadget.com"])
        #expect(pick.results[0].pageURL.absoluteString == "https://www.dyson.com/vacuum-cleaners/cordless/pencilvac")

        let search = try #require(MockBraveImageTransport.searchRequests.first)
        #expect(search.url?.query?.contains("q=dyson%20pencilvac") == true, "the subject alone, as on Wikipedia")
        #expect(search.value(forHTTPHeaderField: "X-Subscription-Token") == "brave-test")
        #expect(MockBraveImageTransport.requests.count == 3, "the search, the download that failed, the one that worked")
        #expect(MockWikipediaTransport.requests.count == 1, "Wikipedia was asked first, and had nothing to summarise")
    }

    @Test func aWikipediaHitNeverAsksBrave() async throws {
        let brave = MockBraveImageTransport.search(search: pencilVacSearch, pictures: pencilVacPictures)
        MockWikipediaTransport.requests = []
        MockWikipediaTransport.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/search/page") { return (200, Data(flagSearch.utf8)) }
            if let key = path.split(separator: "/").last, let body = flagSummaries[String(key)] { return (200, Data(body.utf8)) }
            return (200, pngMagic)   // the picture
        }
        let wikipedia = ImageSearch(timeout: .seconds(2), session: MockWikipediaTransport.session())
        let pick = try await ImageLookup(wikipedia: wikipedia, brave: brave, budget: .seconds(2)).find("dominican flag", decodes: decodesPNG)
        #expect(pick.source == .wikipedia)
        #expect(pick.results.map(\.title) == ["Flag of the Dominican Republic", "Flag of Dominica"])
        #expect(pick.results[0].sourceName == "Wikipedia")
        #expect(MockBraveImageTransport.requests.isEmpty)
    }

    @Test func aBraveMissKeepsTheFallback() async {
        let brave = MockBraveImageTransport.search(search: #"{"type":"images","results":[]}"#)
        await #expect(throws: ImageError.nothingFound("Wikipedia: no image; Brave: no image")) {
            try await lookup(wikipedia: noThumbnailSearch, brave: brave).find("dyson pencilvac", decodes: decodesPNG)
        }
    }

    @Test func nothingThatDownloadsAndDecodesKeepsTheFallback() async {
        // Every original image 404s or is not a picture.
        let brave = MockBraveImageTransport.search(search: pencilVacSearch, pictures: ["https://s.yimg.com/pencilvac.jpg": Data("nope".utf8)])
        await #expect(throws: ImageError.nothingFound("Wikipedia: no image; Brave: 3 results, none downloaded and decoded")) {
            try await lookup(wikipedia: noThumbnailSearch, brave: brave).find("dyson pencilvac", decodes: decodesPNG)
        }
    }

    @Test func aBraveErrorKeepsTheFallbackAndSaysSo() async {
        let brave = MockBraveImageTransport.search(status: 429, search: "slow down")
        await #expect(throws: ImageError.nothingFound("Wikipedia: no image; Brave: http 429: slow down")) {
            try await lookup(wikipedia: noThumbnailSearch, brave: brave).find("dyson pencilvac", decodes: decodesPNG)
        }
    }

    @Test func noKeySkipsBrave() async {
        MockBraveImageTransport.requests = []
        await #expect(throws: ImageError.nothingFound("Wikipedia: no image; Brave: no key")) {
            try await lookup(wikipedia: noThumbnailSearch, brave: nil).find("dyson pencilvac", decodes: decodesPNG)
        }
        #expect(MockBraveImageTransport.requests.isEmpty)
    }

    @Test func aWikipediaErrorIsNotAMissSoBraveIsNotAsked() async {
        let brave = MockBraveImageTransport.search(search: pencilVacSearch, pictures: pencilVacPictures)
        MockWikipediaTransport.handler = { _ in (503, Data("busy".utf8)) }
        MockWikipediaTransport.requests = []
        let wikipedia = ImageSearch(timeout: .seconds(2), session: MockWikipediaTransport.session())
        await #expect(throws: ImageError.http(status: 503, body: "busy")) {
            try await ImageLookup(wikipedia: wikipedia, brave: brave, budget: .seconds(2)).find("x", decodes: decodesPNG)
        }
        #expect(MockBraveImageTransport.requests.isEmpty)
    }

    @Test func aSlowWikipediaIsATimeoutNotAMiss() async {
        let brave = MockBraveImageTransport.search(search: pencilVacSearch, pictures: pencilVacPictures)
        MockWikipediaTransport.handler = { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return (200, Data(noThumbnailSearch.utf8))
        }
        MockWikipediaTransport.requests = []
        let wikipedia = ImageSearch(timeout: .milliseconds(50), session: MockWikipediaTransport.session())
        await #expect(throws: ImageError.timeout) {
            try await ImageLookup(wikipedia: wikipedia, brave: brave, budget: .seconds(2)).find("x", decodes: decodesPNG)
        }
        #expect(MockBraveImageTransport.requests.isEmpty)
    }

    @Test func picturesAreFetchedFromTheRightPlace() async throws {
        let url = URL(string: "https://s.yimg.com/pencilvac.jpg")!
        let brave = MockBraveImageTransport.search(search: "{}", pictures: [url.absoluteString: pngMagic])
        let lookup = ImageLookup(wikipedia: MockWikipediaTransport.search(search: "{}", summaries: [:]), brave: brave)
        let result = ImageResult(title: "x", key: url.absoluteString, imageURL: url, width: 0, height: 0, pageURL: url, source: .brave)
        #expect(try await lookup.data(for: result) == pngMagic)
        #expect(!MockWikipediaTransport.requests.contains { $0.url?.absoluteString.contains("pencilvac") == true }, "a Brave picture never goes through the Wikipedia session")
    }

    @Test func theLogSaysWhichSourceAnswered() throws {
        let summary = ImageSummary(article: "Dyson PencilVac", candidates: 2, latencyMs: 900, source: .brave, outcome: .shown(alternates: 1))
        let line = String(decoding: try DecisionRecord.encoder.encode(summary), as: UTF8.self)
        #expect(line.contains(#""source":"brave""#))
        let old = #"{"article":"Eiffel Tower","candidates":1,"outcome":{"shown":{"alternates":0}}}"#
        #expect(try DecisionRecord.decoder.decode(ImageSummary.self, from: Data(old.utf8)).source == nil, "lines from before Brave still decode")
    }
}
}
