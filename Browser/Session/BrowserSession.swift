import Foundation
import Observation
import WebKit

/// One browsing session: the single web page, the current plan, and the
/// router that turns a query into a plan.
@Observable
@MainActor
final class BrowserSession {
    let page = WebPage()
    private(set) var plans: [CardPlan] = []
    private(set) var lastQuery = ""

    private let router: any Router

    init(router: any Router = LocalRouter()) {
        self.router = router
    }

    func submit(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastQuery = trimmed
        Task {
            let plan = await router.route(trimmed)
            apply(plan)
        }
    }

    private func apply(_ plan: CardPlan) {
        plans = [plan]
        switch plan {
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
