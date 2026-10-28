import Foundation

/// A typed address, which loads as typed with no reading and no Jev; the
/// Google results pages the app loads for words; and a results page read
/// back for the capsule and the log.
public enum QueryParser {
    public static func url(for raw: String) -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return directURL(from: text) ?? searchURL(for: text)
    }

    /// `https://example.com/path`, `example.com`, `news.ycombinator.com/item?id=1`.
    /// Anything with a space, or without a letters-only last label, is a search.
    public static func directURL(from text: String) -> URL? {
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

    /// A Google results page for `text`. A plus is sent as `%2B`, since
    /// Google reads a bare `+` in `q` as a space ("c++" would search "c").
    public static func searchURL(for text: String) -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#")
        var components = URLComponents(string: "https://www.google.com/search")!
        components.percentEncodedQuery = "q=" + (text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        return components.url!
    }

    /// Google's image results for `text`: where an `image` pick goes when
    /// Wikipedia has no picture of the subject, so a request for a picture
    /// still ends in pictures. A results page like any other to the
    /// capsule and the log (`isSearchResults`, `searchTerm`).
    public static func imageSearchURL(for text: String) -> URL {
        var components = URLComponents(url: searchURL(for: text), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery! += "&tbm=isch"
        return components.url!
    }

    /// Google's video results for `text`: where a `video` pick goes, with
    /// the asking already gone ("videos of Pele"). A results page like any
    /// other to the capsule and the log.
    public static func videoSearchURL(for text: String) -> URL {
        var components = URLComponents(url: searchURL(for: text), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery! += "&tbm=vid"
        return components.url!
    }

    /// A Google results page, as opposed to a website.
    public static func isSearchResults(_ url: URL) -> Bool {
        guard let host = url.host() else { return false }
        return host.hasSuffix("google.com") && url.path() == "/search"
    }

    /// The term a Google results page shows results for; nil for any other
    /// page. Google's own pages spell a space as `+`, which `URLComponents`
    /// leaves alone; a literal plus in a term arrives as `%2B` and is kept.
    public static func searchTerm(in url: URL) -> String? {
        guard isSearchResults(url) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .percentEncodedQueryItems?.first(where: { $0.name == "q" })?.value?
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding
    }

    /// The text to show in the address bar for a loaded page: the search
    /// term for a Google results page, the host for anything else.
    public static func displayText(for url: URL?) -> String {
        guard let url, let host = url.host() else { return "" }
        if let term = searchTerm(in: url) { return term }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
