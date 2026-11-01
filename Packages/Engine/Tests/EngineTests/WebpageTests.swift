import Foundation
import Testing
@testable import Engine

/// The open webpage on disk: one line per webpage, round-tripping with its
/// place in the page; the title's fallbacks; what an older recall log row
/// still reads as.
@Suite struct WebpageTests {
    private func roundTrip(_ webpage: Webpage) throws -> Webpage {
        try DecisionRecord.decoder.decode(Webpage.self, from: DecisionRecord.encoder.encode(webpage))
    }

    @Test func aWebpageRoundTripsWithItsPlace() throws {
        let opened = Date(timeIntervalSince1970: 1_792_700_000)   // whole seconds: the file keeps none finer
        let webpage = Webpage(kind: .page, address: URL(string: "https://www.dyson.com/pencilvac?utm_source=x")!, title: "Dyson PencilVac | Dyson", query: "dyson pencilvac", opened: opened, lastSeen: opened.addingTimeInterval(600), scrollY: 420, videoTime: nil)
        let back = try roundTrip(webpage)
        #expect(back == webpage)
        #expect(back.address.absoluteString == "https://www.dyson.com/pencilvac", "kept canonical")
        #expect(back.scrollY == 420 && back.videoTime == nil)
        let json = String(decoding: try DecisionRecord.encoder.encode(webpage), as: UTF8.self)
        #expect(json.contains("\"kind\":\"page\"") && !json.contains("\"parts\""))
        let video = Webpage(kind: .page, address: URL(string: "https://m.youtube.com/watch?v=a")!, title: "Lisbon", opened: opened, videoTime: 73)
        #expect(try roundTrip(video).videoTime == 73)
    }

    @Test func theTitleFallsBackToTheQueryThenTheHost() {
        #expect(Webpage(kind: .page, address: URL(string: "https://www.reddit.com/r/x")!, title: "  ", query: "reddit").title == "reddit")
        #expect(Webpage(kind: .page, address: URL(string: "https://www.reddit.com/r/x")!).title == "www.reddit.com")
        let search = Webpage(kind: .search, address: QueryParser.searchURL(for: "flights to lima"), query: "flights to lima")
        #expect(search.title == "flights to lima" && search.term == "flights to lima")
        #expect(Webpage(kind: .page, address: URL(string: "https://a.example/")!, title: "A").term == nil)
        #expect(Webpage.Kind.images.label == "picture search" && Webpage.Kind.search.symbol == "magnifyingglass")
    }

    @Test func anOlderRecallRowStillReads() throws {
        let row = #"{"matches":1,"picked":"narrative","shortlisted":3,"judged":1,"source":"jev","latencyMs":420}"#
        let summary = try DecisionRecord.decoder.decode(RecallSummary.self, from: Data(row.utf8))
        #expect(summary.matches == 1 && summary.picked == nil && summary.shortlisted == 3, "a kind that is no longer a webpage reads as none")
        let current = try DecisionRecord.decoder.decode(RecallSummary.self, from: Data(#"{"matches":1,"picked":"page"}"#.utf8))
        #expect(current.picked == .page)
    }

    @Test func anOlderPlanSummaryStillReadsItsCount() throws {
        let row = #"{"model":"m","rounds":1,"steps":[],"latencyMs":1,"factsGiven":2,"memoriesGiven":5,"outcome":{"completed":{}}}"#
        let summary = try DecisionRecord.decoder.decode(EngineSummary.self, from: Data(row.utf8))
        #expect(summary.webpagesGiven == 5, "the field's old name is read")
        let back = String(decoding: try DecisionRecord.encoder.encode(summary), as: UTF8.self)
        #expect(back.contains("\"webpagesGiven\":5") && !back.contains("memoriesGiven"))
    }
}
