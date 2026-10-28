import Foundation
import Testing
@testable import Routing

@Suite struct SiteBookTests {
    private let now = Date(timeIntervalSince1970: 1_792_685_600)

    @Test func theSeedAnswersCommonNamesAndAliases() {
        let book = SiteBook.seeded(now: now)
        #expect(book.lookup("youtube")?.url.absoluteString == "https://www.youtube.com")
        #expect(book.lookup("yt")?.url.absoluteString == "https://www.youtube.com")
        #expect(book.lookup("insta")?.url.absoluteString == "https://www.instagram.com")
        #expect(book.lookup("fb")?.host == "www.facebook.com")
        #expect(book.lookup("Zillow")?.host == "www.zillow.com", "case and punctuation aside, the words are the key")
        #expect(book.lookup("The Zillow website") == nil, "no article or trailer list: the reading beside Jev gives the bare name")
        #expect(book.lookup("hacker news") == nil)
        #expect(book.lookup("google docs")?.host == "docs.google.com", "Google's own products are sites, so a bare name is never a search that loses the \"google\"")
        #expect(book.lookup("docs")?.host == "docs.google.com")
        #expect(book.lookup("translate")?.host == "translate.google.com")
        #expect(book.lookup("youtube")?.seeded == true)
        #expect(book.entries.count >= SiteBook.seed.count)
        for (names, address) in SiteBook.seed {
            #expect(URL(string: address)?.host() != nil, "\(address) is a URL with a host")
            #expect(!names.isEmpty)
        }
    }

    @Test func learningStoresTheOriginAndReplacesTheSeed() throws {
        var book = SiteBook.seeded(now: now)
        book.learn("zillow", url: try #require(URL(string: "https://www.zillow.com/homes/austin-tx/?x=1")), now: now)
        let entry = try #require(book.lookup("Zillow"))
        #expect(entry.url.absoluteString == "https://www.zillow.com")
        #expect(entry.seeded == false)
        #expect(entry.uses == 0)
        #expect(entry.learned == now)

        book.learn("hacker news", url: try #require(URL(string: "https://news.ycombinator.com/news")), now: now)
        #expect(book.lookup("Hacker News")?.host == "news.ycombinator.com")
    }

    @Test func touchCountsUsesAndForgetDrops() throws {
        var book = SiteBook.seeded(now: now)
        book.touch("youtube", now: now.addingTimeInterval(60))
        book.touch("YouTube", now: now.addingTimeInterval(120))
        #expect(book.lookup("youtube")?.uses == 2)
        #expect(book.lookup("youtube")?.lastUsed == now.addingTimeInterval(120))
        book.forget("youtube")
        #expect(book.lookup("youtube") == nil)
        #expect(book.lookup("yt") != nil, "an alias is its own entry")
        book.touch("nobody", now: now)
        #expect(book.lookup("nobody") == nil, "touching an unknown name learns nothing")
    }

    @Test func originKeepsSchemeAndHostOnly() {
        #expect(SiteBook.origin(of: URL(string: "https://m.youtube.com/watch?v=a#t")!)?.absoluteString == "https://m.youtube.com")
        #expect(SiteBook.origin(of: URL(string: "HTTP://Example.com/x")!)?.absoluteString == "http://Example.com")
        #expect(SiteBook.origin(of: URL(string: "mailto:a@b.c")!) == nil)
        #expect(SiteBook.origin(of: URL(string: "https:///nohost")!) == nil)
    }

    @Test func learningNeedsANameAndAWebAddress() throws {
        var book = SiteBook()
        book.learn("", url: try #require(URL(string: "https://x.com")), now: now)
        book.learn("x", url: try #require(URL(string: "file:///tmp/a")), now: now)
        #expect(book.entries.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        var book = SiteBook.seeded(now: now)
        book.learn("hacker news", url: try #require(URL(string: "https://news.ycombinator.com")), now: now)
        let data = try DecisionRecord.encoder.encode(book)
        let back = try DecisionRecord.decoder.decode(SiteBook.self, from: data)
        #expect(back == book)
    }
}
