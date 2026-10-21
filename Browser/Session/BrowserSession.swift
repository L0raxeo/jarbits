import Foundation
import Observation
import Routing
import WebKit

/// One browsing session: the single web page, the current plan, and the
/// router that turns a query into a plan.
@Observable
@MainActor
final class BrowserSession {
    let page = WebPage()
    private(set) var plans: [CardPlan] = []
    private(set) var lastQuery = ""
    /// Why the current plan is what it is; shown by the debug ribbon.
    private(set) var lastDecision: RouteDecision?

    private let router: any Router

    init(router: any Router) {
        self.router = router
    }

    func submit(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastQuery = trimmed
        Task {
            let result = await router.route(trimmed)
            apply(result)
        }
    }

    private func apply(_ result: RouteResult) {
        lastDecision = result.decision
        plans = [result.plan]
        switch result.plan {
        case .web(let url):
            _ = page.load(URLRequest(url: url))
        }
    }

    // MARK: Navigation

    var canGoBack: Bool { !page.backForwardList.backList.isEmpty }
    var canGoForward: Bool { !page.backForwardList.forwardList.isEmpty }

    func goBack() {
        guard let item = page.backForwardList.backList.last else { return }
        _ = page.load(item)
    }

    func goForward() {
        guard let item = page.backForwardList.forwardList.first else { return }
        _ = page.load(item)
    }

    func reload() {
        _ = page.reload()
    }

    func stop() {
        page.stopLoading()
    }
}
