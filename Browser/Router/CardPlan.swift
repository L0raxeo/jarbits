import Foundation
import Routing
import Sites

/// What the router decided to show for a query.
///
/// One case per card type. Adding a format means adding a case here,
/// a card view in `Cards/`, and whatever provider fills it in behind the router.
enum CardPlan: Hashable, Sendable {
    /// A full web page: a search results page or a specific site.
    case web(URL)
    /// A model-written answer for `narrative` or `one_line`, streamed by
    /// `AnswerSession`. `history` is the conversation this answer continues,
    /// oldest first; empty for a fresh answer.
    case answer(format: ResponseFormat, query: String, history: [AnswerTurn])
    /// A picture of the thing named, from Wikipedia or Brave, loaded by `ImageSession`.
    case image(query: String)
    /// A one-line answer computed on the device by a `LocalAnswers` rule; `text` carries the format's markup.
    case localAnswer(format: ResponseFormat, query: String, text: String)
    /// Jev's pick for a query that wants something seen before; the session
    /// resolves it from the memories into one of the plans below.
    case recall(query: String)
    /// Several memories matched; a card lists them and a tap replays one.
    /// `title` says what they are when the query asked for a set
    /// ("Everything about Dyson PencilVac", "Last 5 searches"); nil for a
    /// plain choice between candidates.
    case recallPicker([MemoryRecord], title: String?)
    /// A remembered narrative, shown from its saved text with its date.
    case memory(MemoryRecord)
    /// A website asked for by name (what `SiteQuery` left of the query);
    /// the session opens it from the site book or searches for it.
    case site(name: String)
    /// The sites a name might mean; a tap learns one and opens it.
    case siteChoices(name: String, [SiteCandidate])

    /// Which card a plan is, for SwiftUI's identity. An answer that grows
    /// into a conversation keeps its card (named by the thread's first
    /// query, which a device-computed answer shares); any other change of
    /// plan is a new card, so the old one can leave through its transition
    /// instead of changing under the reader.
    var cardID: String {
        switch self {
        case .web: "web"
        case let .answer(_, query, history): "answer:" + (history.first?.query ?? query)
        case .image: "image"
        case let .localAnswer(_, query, _): "answer:" + query   // the thread grown from it is the same card
        case .recall: "recall"
        case .recallPicker: "picker"
        case let .memory(record): "memory:\(record.id)"
        case .site: "site"
        case .siteChoices: "choices"
        }
    }
}
