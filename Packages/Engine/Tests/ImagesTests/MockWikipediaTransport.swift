import Foundation
@testable import Images

/// Serves canned Wikipedia JSON by URL path so the tests never touch the network.
final class MockWikipediaTransport: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (status: Int, body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWikipediaTransport.self]
        return URLSession(configuration: configuration)
    }

    /// A search that routes by path: the search endpoint gets `search`, a
    /// summary endpoint gets the entry for its key, anything else 404s.
    static func search(search searchBody: String, summaries: [String: String], timeout: Duration = .seconds(2)) -> ImageSearch {
        handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/search/page") { return (200, Data(searchBody.utf8)) }
            if let key = path.split(separator: "/").last, let body = summaries[String(key)] { return (200, Data(body.utf8)) }
            return (404, Data("{}".utf8))
        }
        requests = []
        return ImageSearch(timeout: timeout, session: session())
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

/// The search for "dominican flag" as Wikipedia returned it on 2026-10-22,
/// with a thumbnail added to the disambiguation page and a Dominica hit so the
/// skip and alternate rules both have something to do.
let flagSearch = """
{"pages":[
 {"id":459020,"key":"Flag_of_the_Dominican_Republic","title":"Flag of the Dominican Republic","excerpt":"The national <span class=\\"searchmatch\\">flag</span>","matched_title":null,"anchor":null,"description":"","thumbnail":{"mimetype":"image/svg+xml","width":60,"height":40,"duration":null,"url":"//thumb.wikimedia.org/x/60px-Flag_of_the_Dominican_Republic.svg.png"}},
 {"id":71917109,"key":"Dominican_flag","title":"Dominican flag","excerpt":"may refer to","matched_title":null,"anchor":null,"description":"Topics referred to by the same term","thumbnail":{"mimetype":"image/png","width":60,"height":40,"duration":null,"url":"//thumb.wikimedia.org/x/60px-d.png"}},
 {"id":1,"key":"Flag_of_Dominica","title":"Flag of Dominica","excerpt":"The flag of Dominica","matched_title":null,"anchor":null,"description":"National flag","thumbnail":{"mimetype":"image/svg+xml","width":60,"height":30,"duration":null,"url":"//thumb.wikimedia.org/x/60px-Flag_of_Dominica.svg.png"}},
 {"id":11181552,"key":"List_of_flags_of_the_Dominican_Republic","title":"List of flags of the Dominican Republic","excerpt":"is a lists of flags","matched_title":null,"anchor":null,"description":"","thumbnail":null}
]}
"""

let flagSummaries: [String: String] = [
    "Flag_of_the_Dominican_Republic": """
    {"type":"standard","title":"Flag of the Dominican Republic","displaytitle":"<span>Flag of the Dominican Republic</span>","description":"","extract":"The national flag of the Dominican Republic is one of the official national symbols of the nation.",
     "thumbnail":{"source":"https://thumb.wikimedia.org/x/330px-Flag_of_the_Dominican_Republic.svg.png","width":330,"height":220},
     "originalimage":{"source":"https://thumb.wikimedia.org/x/960px-Flag_of_the_Dominican_Republic.svg.png","width":900,"height":600},
     "content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/Flag_of_the_Dominican_Republic"},"mobile":{"page":"https://en.m.wikipedia.org/wiki/Flag_of_the_Dominican_Republic"}}}
    """,
    "Dominican_flag": """
    {"type":"disambiguation","title":"Dominican flag","description":"Topics referred to by the same term","extract":"Dominican flag may refer to:",
     "content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/Dominican_flag"},"mobile":{"page":"https://en.m.wikipedia.org/wiki/Dominican_flag"}}}
    """,
    "Flag_of_Dominica": """
    {"type":"standard","title":"Flag of Dominica","description":"National flag","extract":"The flag of Dominica was adopted on 3 November 1978.",
     "thumbnail":{"source":"https://thumb.wikimedia.org/x/330px-Flag_of_Dominica.svg.png","width":330,"height":165},
     "originalimage":{"source":"https://thumb.wikimedia.org/x/960px-Flag_of_Dominica.svg.png","width":960,"height":480},
     "content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/Flag_of_Dominica"},"mobile":{"page":"https://en.m.wikipedia.org/wiki/Flag_of_Dominica"}}}
    """,
]
