import Foundation
import Engine

/// Finds pictures for a subject with Brave's image search, the second source
/// behind Wikipedia: one request, with the key, for a subject Wikipedia has
/// no article on (a product from this year, say). Each result names the
/// page the picture sits on; the card links there instead of an article.
/// Costs a request per miss on Wikipedia, so `ImageLookup` only asks when
/// Wikipedia answered and had nothing.
public struct BraveImageSearch: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.search.brave.com")!
    /// Results asked for; the first that downloads and decodes is shown, up
    /// to two of the others are alternates.
    public static let searchCount = 5
    public static let safeSearch = "strict"
    public static let defaultTimeout: Duration = .seconds(6)

    public var apiKey: String
    public var baseURL: URL
    public var timeout: Duration
    var session: URLSession

    public init(apiKey: String, baseURL: URL = BraveImageSearch.defaultBaseURL, timeout: Duration = BraveImageSearch.defaultTimeout, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
    }

    /// Up to `searchCount` results with a full-size image URL, in Brave's
    /// order. `subject` is searched as given: the caller has already taken
    /// the asking off the query (`ImageQuery`).
    public func find(_ subject: String) async throws(ImageError) -> [ImageResult] {
        do {
            return try await withTimeout(timeout) { try await search(subject) }
        } catch is TimeoutError {
            throw .timeout
        } catch let error as ImageError {
            throw error
        } catch {
            throw .transport(String(describing: error))
        }
    }

    /// The bytes of a picture from the source site: no key, no Wikipedia user agent.
    public func data(for url: URL) async throws(ImageError) -> Data {
        do {
            return try await withTimeout(timeout) {
                var request = URLRequest(url: url)
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ImageError.transport("not an HTTP response") }
                guard (200..<300).contains(http.statusCode) else {
                    throw ImageError.http(status: http.statusCode, body: String(decoding: data.prefix(300), as: UTF8.self))
                }
                return data
            }
        } catch is TimeoutError {
            throw .timeout
        } catch let error as ImageError {
            throw error
        } catch {
            throw .transport(String(describing: error))
        }
    }

    /// The results that carry a full-size image and a page, in order.
    static func results(from response: ImageSearchResponse) -> [ImageResult] {
        response.results.compactMap { result in
            guard let image = result.properties?.url, let imageURL = URL(string: image),
                  let pageURL = URL(string: result.url) else { return nil }
            let publisher = result.source?.isEmpty == false ? result.source : nil
            let title = result.title?.isEmpty == false ? result.title! : (publisher ?? pageURL.host() ?? result.url)
            let description = publisher
            return ImageResult(
                title: title, key: result.url, description: description, imageURL: imageURL,
                width: result.properties?.width ?? 0, height: result.properties?.height ?? 0,
                pageURL: pageURL, source: .brave
            )
        }
    }

    private func search(_ subject: String) async throws -> [ImageResult] {
        var components = URLComponents(url: baseURL.appending(path: "res/v1/images/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: subject),
            URLQueryItem(name: "count", value: String(Self.searchCount)),
            URLQueryItem(name: "safesearch", value: Self.safeSearch),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ImageError.transport("not an HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw ImageError.http(status: http.statusCode, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        let decoded: ImageSearchResponse
        do {
            decoded = try JSONDecoder().decode(ImageSearchResponse.self, from: data)
        } catch {
            throw ImageError.decoding(String(describing: error))
        }
        let found = Self.results(from: decoded)
        guard !found.isEmpty else { throw ImageError.noImage }
        return found
    }
}

// MARK: Wire shapes (only what is read)

struct ImageSearchResponse: Decodable {
    struct Result: Decodable {
        /// The original image on the source site; Brave does not always know its size.
        struct Properties: Decodable {
            var url: String?
            var width: Int?
            var height: Int?
        }
        var title: String?
        /// The page the picture sits on.
        var url: String
        /// The publisher, usually the page's host.
        var source: String?
        var properties: Properties?
    }
    var results: [Result]
}
