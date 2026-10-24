import Foundation
import Routing

/// The image part of `ROUTING.md`: where a picture comes from, Wikipedia then Brave, and what is logged.
public enum ImagesReport {
    public static func markdown() -> String {
        func quoted(_ phrases: [String]) -> String { phrases.map { "\"\($0)\"" }.joined(separator: ", ") }
        var out: [String] = []
        out.append("## After routing: Wikipedia images")
        out.append("")
        out.append("An `image` pick is filled by `ImageLookup` in `Packages/Routing/Sources/Images` from two sources in order: Wikipedia (`ImageSearch`), free and without a key, whose article carries the picture's licence; then, only when Wikipedia answered and had nothing, Brave's image search (`BraveImageSearch`) with the same key as the site search (`BRAVE_API_KEY`, $5 per 1,000 requests), for a subject Wikipedia has no article on (a product from this year, say). Every Wikipedia request sends `User-Agent: \(ImageSearch.defaultUserAgent)`.")
        out.append("")
        out.append("What is searched is the subject alone: `ImageQuery` takes the asking off the query (\"show me a picture of the eiffel tower\" → \"eiffel tower\", \"what does a capybara look like\" → \"capybara\", \"Dominican flag, I said.\" → \"Dominican flag\"), as typed, and leaves a bare subject as it is. Wikipedia's ranking turns on every word: \"Dominican flag, I said\" puts the flag of Panama first. The card, the memory and the log keep the spoken words.")
        out.append("")
        out.append("- Corrections, any number, at the front: \(quoted(ImageQuery.corrections))")
        out.append("- Leads, any number, before the opener: \(quoted(ImageQuery.leads))")
        out.append("- Openers: \(quoted(ImageQuery.openers))")
        out.append("- Articles, before and after the picture phrase: \(quoted(ImageQuery.articles))")
        out.append("- The picture phrase: \(quoted(ImageQuery.nounsOf))")
        out.append("- Trailers, any number, at the end: \(quoted(ImageQuery.trailers))")
        out.append("")
        out.append("1. `GET \(ImageSearch.defaultBaseURL)/w/rest.php/v1/search/page?q=<subject>&limit=\(ImageSearch.searchLimit)`: article candidates in rank order. Hits without a `thumbnail` are dropped; the first \(ImageSearch.candidateLimit) remain.")
        out.append("2. `GET \(ImageSearch.defaultBaseURL)/api/rest_v1/page/summary/<key>` for each, in parallel: `type` must be `standard` (disambiguation pages are dropped) and `originalimage` must exist. An SVG comes back as a PNG render of about 960 px.")
        out.append("3. The first remaining article's picture is downloaded and decoded before the card is shown; the others, up to two, are alternates.")
        out.append("")
        out.append("Wikipedia found nothing with a picture (not an error, not a timeout: those keep the fallback below without asking Brave), and a Brave key is configured:")
        out.append("")
        out.append("4. `GET \(BraveImageSearch.defaultBaseURL)/res/v1/images/search?q=<subject>&count=\(BraveImageSearch.searchCount)&safesearch=\(BraveImageSearch.safeSearch)` with `X-Subscription-Token`: the same subject, in Brave's order. A result without an original image URL (`properties.url`) is dropped.")
        out.append("5. Each result's full-size image is downloaded from its site, in order, until one decodes: that is the picture; up to two of the results after it are alternates. The card's link goes to the page the picture sits on, named by its host (\"dyson.com\") where the Wikipedia link says \"Wikipedia\".")
        out.append("")
        out.append("Each request has \(ImageSearch().timeout.components.seconds) s to reply, and each source \(ImageLookup.defaultBudget.components.seconds) s for its search and the first download. Nothing from either source, no key, any failure, or a timeout falls back to Google's image results for the subject (`QueryParser.imageSearchURL`), so a request for a picture still ends in pictures.")
        out.append("")
        out.append("| Outcome | Shown | Logged as |")
        out.append("|---|---|---|")
        out.append("| A Wikipedia picture decoded | The image card, with alternates when there are any, linked to the article | `shown(alternates:)` with the article, candidate count and latency, `source: wikipedia` |")
        out.append("| Wikipedia had nothing, a Brave picture decoded | The image card, with up to two alternates, linked to the page | `shown(alternates:)` with the result's title, `source: brave` |")
        out.append("| Wikipedia had nothing, no Brave key | Google Images for the subject | `fellBackToWeb(\"Wikipedia: no image; Brave: no key\")` |")
        out.append("| Wikipedia had nothing, Brave had nothing or failed | Google Images for the subject | `fellBackToWeb(\"Wikipedia: no image; Brave: …\")` with what Brave did |")
        out.append("| Wikipedia failed or timed out | Google Images for the subject | `fellBackToWeb(reason)`; Brave is not asked |")
        out.append("")
        out.append("A Wikipedia article's page carries the image's licence and author; a Brave picture is whatever its site published, which is why Wikipedia goes first.")
        return out.joined(separator: "\n") + "\n"
    }
}
