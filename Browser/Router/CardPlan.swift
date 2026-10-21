import Foundation

/// What the router decided to show for a query.
///
/// One case per response format. Adding a format means adding a case here,
/// a card view in `Cards/`, and whatever provider fills it in behind the router.
enum CardPlan: Hashable, Sendable {
    /// A full web page: a search results page or a specific site.
    case web(URL)
}
