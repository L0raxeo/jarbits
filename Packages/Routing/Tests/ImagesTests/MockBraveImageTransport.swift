import Foundation
@testable import Images

/// Serves canned Brave image-search JSON and picture bytes by URL so the
/// tests never touch the network. Its own `URLProtocol`, so a lookup can
/// run with `MockWikipediaTransport` on the Wikipedia side at the same time.
final class MockBraveImageTransport: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (status: Int, body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockBraveImageTransport.self]
        return URLSession(configuration: configuration)
    }

    /// A search that routes by URL: the images endpoint gets `search`, a
    /// picture URL gets its entry in `pictures`, anything else 404s.
    static func search(status: Int = 200, search searchBody: String, pictures: [String: Data] = [:], timeout: Duration = .seconds(2)) -> BraveImageSearch {
        handler = { request in
            let url = request.url?.absoluteString ?? ""
            if request.url?.path == "/res/v1/images/search" { return (status, Data(searchBody.utf8)) }
            if let bytes = pictures[url] { return (200, bytes) }
            return (404, Data("not here".utf8))
        }
        requests = []
        return BraveImageSearch(apiKey: "brave-test", timeout: timeout, session: session())
    }

    /// The search requests alone, without the picture downloads.
    static var searchRequests: [URLRequest] { requests.filter { $0.url?.path == "/res/v1/images/search" } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The first bytes of a PNG; what the tests count as "decodes".
let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
let decodesPNG: @Sendable (Data) -> Bool = { $0.starts(with: pngMagic) }

/// A Wikipedia search whose only hit has no thumbnail: a miss, not an error.
let noThumbnailSearch = #"{"pages":[{"id":1,"key":"Dyson","title":"Dyson","excerpt":"","matched_title":null,"anchor":null,"description":"","thumbnail":null}]}"#

/// An image search for "dyson pencilvac" in the shape Brave documents: the
/// first result's original image is gone from its site, the second is a
/// PNG, the third has no size, the fourth has no original URL at all.
let pencilVacSearch = """
{"type":"images","query":{"original":"dyson pencilvac","altered":"","spellcheck_off":false,"show_strict_warning":false},
 "results":[
  {"type":"image_result","title":"Dyson PencilVac review","url":"https://www.theverge.com/dyson-pencilvac-review","source":"theverge.com","page_fetched":"2025-06-01T00:00:00Z","thumbnail":{"src":"https://imgs.search.brave.com/t1.jpg"},"properties":{"url":"https://cdn.theverge.com/pencilvac-hero.jpg","placeholder":"https://imgs.search.brave.com/p1.jpg","width":2000,"height":1333},"meta_url":{"scheme":"https","netloc":"theverge.com","hostname":"www.theverge.com","favicon":"https://imgs.search.brave.com/v.ico","path":"/dyson-pencilvac-review"},"confidence":"high"},
  {"type":"image_result","title":"Dyson PencilVac","url":"https://www.dyson.com/vacuum-cleaners/cordless/pencilvac","source":"dyson.com","page_fetched":"2025-06-01T00:00:00Z","thumbnail":{"src":"https://imgs.search.brave.com/t2.jpg"},"properties":{"url":"https://dyson-h.assetsadobe2.com/is/image/content/dam/dyson/pencilvac.png","placeholder":"https://imgs.search.brave.com/p2.jpg","width":1200,"height":800},"confidence":"high"},
  {"type":"image_result","title":"","url":"https://www.engadget.com/pencilvac","source":"engadget.com","page_fetched":"2025-06-01T00:00:00Z","thumbnail":{"src":"https://imgs.search.brave.com/t3.jpg"},"properties":{"url":"https://s.yimg.com/pencilvac.jpg","placeholder":"https://imgs.search.brave.com/p3.jpg"},"confidence":"medium"},
  {"type":"image_result","title":"PencilVac launch","url":"https://x.com/dyson/status/1","source":"x.com","page_fetched":"2025-06-01T00:00:00Z","thumbnail":{"src":"https://imgs.search.brave.com/t4.jpg"},"properties":{"placeholder":"https://imgs.search.brave.com/p4.jpg"},"confidence":"low"}
 ]}
"""
