import Foundation
import Engine

/// The site half of `ENGINE.md`: where candidate sites come from when a
/// name is unknown, and how the book learns.
public enum SitesReport {
    public static func markdown() -> String {
        var out: [String] = []
        out.append("## After routing: sites")
        out.append("")
        out.append("A `site` pick names a website. The name is what the extractor reads out of the read words (\"can you pull up youtube\" → \"youtube\"; see \"The reading beside Jev\"), or the words as they are when it read none. The site book on the device (`SiteBook`: \(SiteBook.seed.count) seeded sites under \(SiteBook.seeded().entries.count) names, plus whatever has been learned) answers a known name at once; an unknown name is searched by `SiteSearch` in `Packages/Engine/Sources/Sites`, with a Brave Search API key (`BRAVE_API_KEY`).")
        out.append("")
        out.append("1. `GET \(SiteSearch.defaultBaseURL)/res/v1/web/search?q=<name>&count=\(SiteSearch.searchCount)&result_filter=web`, header `X-Subscription-Token`. Only `web.results` is read: title, url, description, and the result's favicon when it carries one (`meta_url.favicon` or `profile.img`), else Google's public favicon service for the host.")
        out.append("2. One result per host (`www.` aside), in Brave's order, the first \(SiteSearch.candidateLimit): the choices card.")
        out.append("3. The site tapped is learned under the name, as its origin (scheme and host), and opened. The next time the name is asked for it opens straight away, with no model and no search.")
        out.append("")
        out.append("No key, no result, any failure, or \(SiteSearch.defaultTimeout.components.seconds) s without a reply shows the Google results page for the name instead, and the first site tapped off it is learned the same way.")
        out.append("")
        out.append("| Outcome | Shown | Logged as |")
        out.append("|---|---|---|")
        out.append("| The book knows the name | That site | `site` summary `opened` with the host |")
        out.append("| Candidates found | The choices card | `choices` with the count and latency |")
        out.append("| No key, nothing found, or an error | Web results for the name | `results` with the reason |")
        out.append("| Over a site opened by name, `rejects` at or above \(EngineRequest.rejectionThreshold.formatted()) on a site pick | The choices card again, the name forgotten | `rejected` |")
        return out.joined(separator: "\n") + "\n"
    }
}
