import Foundation
@testable import Sites

/// Serves canned Brave JSON so the tests never touch the network.
final class MockBraveTransport: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (status: Int, body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockBraveTransport.self]
        return URLSession(configuration: configuration)
    }

    static func search(status: Int = 200, body: String, timeout: Duration = .seconds(2)) -> SiteSearch {
        handler = { _ in (status, Data(body.utf8)) }
        requests = []
        return SiteSearch(apiKey: "brave-test", timeout: timeout, session: session())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A web search for "hacker news" in the shape Brave documents: two results
/// on one host (one with `www.`), one without a favicon, and one from a
/// vertical the app does not read.
let hackerNewsSearch = """
{"type":"search","query":{"original":"hacker news","more_results_available":true},
 "web":{"type":"search","results":[
  {"title":"Hacker News","url":"https://news.ycombinator.com/","description":"Hacker News new | past | comments","profile":{"name":"Hacker News","url":"https://news.ycombinator.com/","long_name":"news.ycombinator.com","img":"https://imgs.search.brave.com/hn-profile.png"},"meta_url":{"scheme":"https","netloc":"news.ycombinator.com","hostname":"news.ycombinator.com","favicon":"https://imgs.search.brave.com/hn.ico","path":""}},
  {"title":"Hacker News: New","url":"https://www.news.ycombinator.com/newest","description":"","meta_url":{"scheme":"https","netloc":"news.ycombinator.com","hostname":"www.news.ycombinator.com","favicon":"https://imgs.search.brave.com/hn2.ico","path":"/newest"}},
  {"title":"Hacker News - Wikipedia","url":"https://en.wikipedia.org/wiki/Hacker_News","description":"Hacker News is a social news website."},
  {"title":"Hacker News (@hackernews)","url":"https://x.com/hackernews","description":"","profile":{"name":"X","url":"https://x.com","long_name":"x.com","img":"https://imgs.search.brave.com/x.png"}},
  {"title":"thehackernews.com","url":"https://thehackernews.com/","description":"Cybersecurity news."},
  {"title":"HN Search","url":"https://hn.algolia.com/","description":"Search Hacker News."},
  {"title":"Hacker Newsletter","url":"https://hackernewsletter.com/","description":"Weekly."}
 ]},
 "videos":{"type":"videos","results":[{"title":"HN explained","url":"https://www.youtube.com/watch?v=1"}]}}
"""
