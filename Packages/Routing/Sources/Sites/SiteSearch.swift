import Foundation
import Routing

/// One site a name might mean.
public struct SiteCandidate: Sendable, Hashable, Codable {
    public var title: String
    public var url: URL
    public var host: String
    public var description: String?
    /// The site's icon: Brave's copy when the result carries one, else
    /// Google's public favicon service for the host.
    public var favicon: URL?

    public init(title: String, url: URL, host: String, description: String? = nil, favicon: URL? = nil) {
        self.title = title
        self.url = url
        self.host = host
        self.description = description
        self.favicon = favicon
    }
}

public enum SiteError: Error, Sendable, Equatable {
    case transport(String)
    case timeout
    case http(status: Int, body: String)
    case decoding(String)
    /// The search returned no web results.
    case noResults
}

/// Finds the sites a name might mean, with Brave's web search: one request,
/// the first few results one per host. Only an unknown name costs a
/// request; the site book answers a known name with no search.
public struct SiteSearch: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.search.brave.com")!
    /// Results asked for; more than are shown, since several may share a host.
    public static let searchCount = 8
    /// Candidates shown at most.
    public static let candidateLimit = 5
    public static let defaultTimeout: Duration = .seconds(6)

    public var apiKey: String
    public var baseURL: URL
    public var timeout: Duration
    var session: URLSession

    public init(apiKey: String, baseURL: URL = SiteSearch.defaultBaseURL, timeout: Duration = SiteSearch.defaultTimeout, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
    }

    /// Up to `candidateLimit` sites, best match first, one per host.
    public func find(_ name: String) async throws(SiteError) -> [SiteCandidate] {
        do {
            return try await withTimeout(timeout) { try await search(name) }
        } catch is TimeoutError {
            throw .timeout
        } catch let error as SiteError {
            throw error
        } catch {
            throw .transport(String(describing: error))
        }
    }

    /// Where a host's icon can be fetched without a key.
    public static func fallbackFavicon(for host: String) -> URL? {
        URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)")
    }

    /// The results, one per host (`www.` aside), in order, cut to the limit.
    static func candidates(from response: WebSearchResponse) -> [SiteCandidate] {
        var seen: Set<String> = []
        var out: [SiteCandidate] = []
        for result in response.web?.results ?? [] {
            guard let url = URL(string: result.url), let host = url.host(), !host.isEmpty else { continue }
            let site = host.lowercased().hasPrefix("www.") ? String(host.lowercased().dropFirst(4)) : host.lowercased()
            guard seen.insert(site).inserted else { continue }
            let icon = (result.metaUrl?.favicon ?? result.profile?.img).flatMap(URL.init(string:)) ?? fallbackFavicon(for: host)
            let description = result.description?.isEmpty == false ? result.description : nil
            out.append(SiteCandidate(title: result.title, url: url, host: host, description: description, favicon: icon))
            if out.count == candidateLimit { break }
        }
        return out
    }

    private func search(_ name: String) async throws -> [SiteCandidate] {
        var components = URLComponents(url: baseURL.appending(path: "res/v1/web/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "count", value: String(Self.searchCount)),
            URLQueryItem(name: "result_filter", value: "web"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SiteError.transport("not an HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw SiteError.http(status: http.statusCode, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        let decoded: WebSearchResponse
        do {
            decoded = try JSONDecoder().decode(WebSearchResponse.self, from: data)
        } catch {
            throw SiteError.decoding(String(describing: error))
        }
        let found = Self.candidates(from: decoded)
        guard !found.isEmpty else { throw SiteError.noResults }
        return found
    }
}

// MARK: Wire shapes (only what is read)

struct WebSearchResponse: Decodable {
    struct Web: Decodable {
        var results: [Result]
    }
    struct Result: Decodable {
        struct Profile: Decodable { var img: String? }
        struct MetaURL: Decodable { var favicon: String? }
        var title: String
        var url: String
        var description: String?
        var profile: Profile?
        var metaUrl: MetaURL?

        enum CodingKeys: String, CodingKey {
            case title, url, description, profile
            case metaUrl = "meta_url"
        }
    }
    var web: Web?
}
