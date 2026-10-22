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
}
