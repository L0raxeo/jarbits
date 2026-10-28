import Foundation
import Engine
import Sites

/// What a layer shows.
///
/// One case per card type. Adding a card means adding a case here, a card
/// view in `ResultView`, and the instinct that opens it.
enum CardPlan: Hashable, Sendable {
    /// A full web page: a search results page or a specific site.
    case web(URL)
    /// A model-written answer for `narrative` or `one_line`, streamed by
    /// `AnswerSession`. `history` is the conversation this answer continues,
    /// oldest first; empty for a fresh answer. `earlier` is what else in
    /// this session the query depends on (a search, a page read), listed
    /// for the model under its context block; empty for a query that stands
    /// alone.
    case answer(format: Instinct, query: String, history: [AnswerTurn], earlier: [Exchange])
    /// A picture of the subject, from Wikipedia or Brave, loaded by `ImageSession`.
    case image(subject: String)
    /// The time from the device clock; `text` carries the one-line markup.
    case time(query: String, text: String)
    /// Several memories matched; a card lists them and a tap replays one.
    /// `title` says what they are when the query asked for a set
    /// ("Everything about Dyson PencilVac", "Last 5 searches"); nil for a
    /// plain choice between candidates.
    case recallPicker([MemoryRecord], title: String?)
    /// A remembered narrative, shown from its saved text with its date.
    case memory(MemoryRecord)
    /// The sites a name might mean; a tap learns one and opens it.
    case siteChoices(name: String, [SiteCandidate])

    /// Which card a plan is, for the console: a short name, an answer's
    /// carrying the thread's first query (which a time answer shares).
    /// The screen keys cards by their layer, not by this.
    var cardID: String {
        switch self {
        case .web: "web"
        case let .answer(_, query, history, _): "answer:" + (history.first?.query ?? query)
        case .image: "image"
        case let .time(query, _): "answer:" + query   // the thread grown from it is the same card
        case .recallPicker: "picker"
        case let .memory(record): "memory:\(record.id)"
        case .siteChoices: "choices"
        }
    }
}
