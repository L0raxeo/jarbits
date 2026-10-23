import Foundation
import Routing

/// The device's own rules before any model: a query `LocalAnswers` can answer
/// (today, the time in a named place) becomes a one-line card at once, with
/// no key and no network; everything else goes to `inner`. Order against the
/// address check inside `inner` does not matter: an address has no spaces,
/// and every local rule needs several words.
struct LocalFirstRouter: Router {
    let inner: any Router

    func route(_ query: String) async -> RouteResult {
        if let local = LocalAnswers.answer(query) {
            return RouteResult(
                plan: .localAnswer(format: local.format, query: query, text: local.text),
                decision: .local(local.rule, format: local.format)
            )
        }
        return await inner.route(query)
    }
}
