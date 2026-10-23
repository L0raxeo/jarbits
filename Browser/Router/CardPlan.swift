import Foundation
import Routing

/// What the router decided to show for a query.
///
/// One case per card type. Adding a format means adding a case here,
/// a card view in `Cards/`, and whatever provider fills it in behind the router.
enum CardPlan: Hashable, Sendable {
    /// A full web page: a search results page or a specific site.
    case web(URL)
    /// A model-written answer for `narrative` or `one_line`, streamed by `AnswerSession`.
    case answer(format: ResponseFormat, query: String)
    /// A Wikipedia picture of the thing named, loaded by `ImageSession`.
    case image(query: String)
    /// A one-line answer computed on the device by a `LocalAnswers` rule; `text` carries the format's markup.
    case localAnswer(format: ResponseFormat, query: String, text: String)
    /// Jev's pick for a query that wants something seen before; the session
    /// resolves it from the memories into one of the plans below.
    case recall(query: String)
    /// Several memories matched; a card lists them and a tap replays one.
    case recallPicker([MemoryRecord])
    /// A remembered narrative, shown from its saved text with its date.
    case memory(MemoryRecord)
}
