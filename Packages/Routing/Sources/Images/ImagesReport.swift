import Foundation
import Routing

/// The image half of `ROUTING.md`: where a picture comes from and what is logged.
public enum ImagesReport {
    public static func markdown() -> String {
        func quoted(_ phrases: [String]) -> String { phrases.map { "\"\($0)\"" }.joined(separator: ", ") }
        var out: [String] = []
        out.append("## After routing: Wikipedia images")
        out.append("")
        out.append("An `image` pick is filled from Wikipedia, free and without a key, by `ImageSearch` in `Packages/Routing/Sources/Images`. Every request sends `User-Agent: \(ImageSearch.defaultUserAgent)`.")
        out.append("")
        out.append("What is searched is the subject alone: `ImageQuery` takes the asking off the query (\"show me a picture of the eiffel tower\" → \"eiffel tower\", \"what does a capybara look like\" → \"capybara\"), as typed, and leaves a bare subject as it is. The card, the memory and the log keep the spoken words.")
        out.append("")
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
        out.append("No candidate with a picture, any failure, or \(ImageSearch().timeout.components.seconds) s without a reply per step falls back to web results.")
        out.append("")
        out.append("| Outcome | Shown | Logged as |")
        out.append("|---|---|---|")
        out.append("| A picture decoded | The image card, with alternates when there are any | `shown(alternates:)` with the article, candidate count and latency |")
        out.append("| Nothing with a picture, or an error | Web results | `fellBackToWeb(reason)` |")
        out.append("")
        out.append("The article's page carries the image's licence and author; the card links to it.")
        return out.joined(separator: "\n") + "\n"
    }
}
