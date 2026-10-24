import Foundation
import Routing

/// One picture: a Wikipedia article's lead image, or a Brave image result.
public struct ImageResult: Sendable, Equatable {
    public var title: String
    /// The article key, as in its URL; for a Brave result, the page URL.
    public var key: String
    public var description: String?
    /// The full-size image. Wikipedia renders an SVG as a PNG of about 960 px;
    /// Brave gives the original on the source site.
    public var imageURL: URL
    /// Brave does not always know the size; then both are 0.
    public var width: Int
    public var height: Int
    /// The article, or the page the picture sits on.
    public var pageURL: URL
    public var source: ImageSource

    public init(title: String, key: String, description: String? = nil, imageURL: URL, width: Int, height: Int, pageURL: URL, source: ImageSource = .wikipedia) {
        self.title = title
        self.key = key
        self.description = description
        self.imageURL = imageURL
        self.width = width
        self.height = height
        self.pageURL = pageURL
        self.source = source
    }

    /// What the card's link is called: "Wikipedia", or the page's host
    /// without `www.` for a Brave result.
    public var sourceName: String {
        switch source {
        case .wikipedia: return "Wikipedia"
        case .brave:
            let host = (pageURL.host() ?? "").lowercased()
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : (host.isEmpty ? "Source" : host)
        }
    }
}

public enum ImageError: Error, Sendable, Equatable {
    case transport(String)
    case timeout
    case http(status: Int, body: String)
    case decoding(String)
    /// The search found nothing with a picture.
    case noImage
    /// Every source was tried and none gave a picture; the detail says what
    /// each one did, for the log.
    case nothingFound(String)

    /// One line for the log.
    public var reason: String {
        switch self {
        case let .transport(message): "transport: \(message)"
        case .timeout: "timeout"
        case let .http(status, body): "http \(status): \(body)"
        case let .decoding(message): "decoding: \(message)"
        case .noImage: "no image"
        case let .nothingFound(detail): detail
        }
    }
}

/// Finds a picture for a query on Wikipedia, free and without a key: the
/// REST page search gives article candidates, the page summary of each gives
/// its lead image. Disambiguation pages and articles without an image are
/// skipped. Results keep the search order, so the first is the best match
/// and the rest are alternates. `ImageLookup` runs this first and
/// `BraveImageSearch` behind it.
public struct ImageSearch: Sendable {
    public static let defaultBaseURL = URL(string: "https://en.wikipedia.org")!
    /// Wikimedia asks every client for a descriptive user agent.
    public static let defaultUserAgent = "Browser/0.1 (com.lorcancheng.browser)"
    /// How many search hits are looked at, and how many summaries are fetched.
    public static let searchLimit = 5
    public static let candidateLimit = 3

    public var baseURL: URL
    public var userAgent: String
    public var timeout: Duration
    var session: URLSession

    public init(
        baseURL: URL = ImageSearch.defaultBaseURL,
        userAgent: String = ImageSearch.defaultUserAgent,
        timeout: Duration = .seconds(6),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.timeout = timeout
        self.session = session
    }

    /// Up to `candidateLimit` articles with pictures, best match first. The
    /// asking around the subject ("show me a picture of", "what does … look
    /// like") is left out of the search (`ImageQuery`).
    public func find(_ query: String) async throws(ImageError) -> [ImageResult] {
        do {
            return try await withTimeout(timeout) { try await search(ImageQuery.subject(for: query)) }
        } catch is TimeoutError {
            throw .timeout
        } catch let error as ImageError {
            throw error
        } catch {
            throw .transport(String(describing: error))
        }
    }

    /// The bytes of a picture, with the same user agent.
    public func data(for url: URL) async throws(ImageError) -> Data {
        do {
            return try await withTimeout(timeout) { try await get(url, accept: "image/*") }
        } catch is TimeoutError {
            throw .timeout
        } catch let error as ImageError {
            throw error
        } catch {
            throw .transport(String(describing: error))
        }
    }

    // MARK: Wikipedia

    private func search(_ query: String) async throws -> [ImageResult] {
        var components = URLComponents(url: baseURL.appending(path: "w/rest.php/v1/search/page"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(Self.searchLimit))]
        let data = try await get(components.url!, accept: "application/json")
        let response: SearchResponse
        do {
            response = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw ImageError.decoding("search: \(error)")
        }
        let candidates = response.pages.filter { $0.thumbnail != nil }.prefix(Self.candidateLimit)
        guard !candidates.isEmpty else { throw ImageError.noImage }

        // Summaries in parallel; a candidate that fails is just dropped.
        let keys = candidates.map(\.key)
        let summaries: [Int: Summary] = await withTaskGroup(of: (Int, Summary?).self) { group in
            for (index, key) in keys.enumerated() {
                group.addTask { (index, try? await summary(forKey: key)) }
            }
            var found: [Int: Summary] = [:]
            for await (index, summary) in group {
                if let summary { found[index] = summary }
            }
            return found
        }
        let results = keys.indices.compactMap { index -> ImageResult? in
            guard let summary = summaries[index], summary.type == "standard",
                  let image = summary.originalimage, let imageURL = URL(string: image.source),
                  let pageURL = URL(string: summary.contentUrls.desktop.page) else { return nil }
            let description = summary.description?.isEmpty == false ? summary.description : nil
            return ImageResult(title: summary.title, key: keys[index], description: description, imageURL: imageURL, width: image.width, height: image.height, pageURL: pageURL)
        }
        guard !results.isEmpty else { throw ImageError.noImage }
        return results
    }

    private func summary(forKey key: String) async throws -> Summary {
        let url = baseURL.appending(path: "api/rest_v1/page/summary/\(key)")
        let data = try await get(url, accept: "application/json")
        do {
            return try JSONDecoder().decode(Summary.self, from: data)
        } catch {
            throw ImageError.decoding("summary: \(error)")
        }
    }

    private func get(_ url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ImageError.transport("not an HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw ImageError.http(status: http.statusCode, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        return data
    }
}

// MARK: Wire shapes (only what is read)

struct SearchResponse: Decodable {
    struct Page: Decodable {
        var key: String
        var title: String
        var description: String?
        var thumbnail: Thumbnail?
    }
    struct Thumbnail: Decodable {
        var url: String
    }
    var pages: [Page]
}

struct Summary: Decodable {
    struct Image: Decodable {
        var source: String
        var width: Int
        var height: Int
    }
    struct ContentURLs: Decodable {
        struct Pages: Decodable { var page: String }
        var desktop: Pages
    }
    var type: String
    var title: String
    var description: String?
    var originalimage: Image?
    var contentUrls: ContentURLs

    enum CodingKeys: String, CodingKey {
        case type, title, description, originalimage
        case contentUrls = "content_urls"
    }
}
