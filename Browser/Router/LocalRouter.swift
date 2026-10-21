import Foundation

/// Every query becomes a web card: URL-looking input loads directly,
/// anything else becomes a Google search.
struct LocalRouter: Router {
    func route(_ query: String) async -> CardPlan {
        .web(QueryParser.url(for: query))
    }
}

/// Decides whether typed text is an address or a search.
enum QueryParser {
    static func url(for raw: String) -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return directURL(from: text) ?? searchURL(for: text)
    }

    /// `https://example.com/path`, `example.com`, `news.ycombinator.com/item?id=1`.
    /// Anything with a space, or without a letters-only last label, is a search.
    static func directURL(from text: String) -> URL? {
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host() != nil {
            return url
        }

        let hostPart = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        let labels = hostPart.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty }),
              let tld = labels.last,
              tld.count >= 2,
              tld.allSatisfy(\.isLetter)
        else { return nil }

        return URL(string: "https://" + text)
    }

    static func searchURL(for text: String) -> URL {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url!
    }

    /// The text to show in the address bar for a loaded page: the search
    /// query for a Google results page, the host for anything else.
    static func displayText(for url: URL?) -> String {
        guard let url, let host = url.host() else { return "" }
        if host.hasSuffix("google.com"), url.path() == "/search",
           let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
               .queryItems?.first(where: { $0.name == "q" })?.value {
            return query
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
