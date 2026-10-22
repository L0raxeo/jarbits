import Answers
import Foundation
import Observation
import Routing
import WebKit

/// One browsing session: the single web page, the current plan, the router
/// that turns a query into a plan, and the answer stream for answer plans.
@Observable
@MainActor
final class BrowserSession {
    let page = WebPage()
    /// Streams Gemini answers; nil when no Gemini key is configured, in which
    /// case the router never produces an answer plan.
    let answer: AnswerSession?
    private(set) var plans: [CardPlan] = []
    private(set) var lastQuery = ""
    /// Why the current plan is what it is; shown by the debug ribbon.
    private(set) var lastDecision: RouteDecision?

    private let router: any Router
    private let log: DecisionLog

    init(router: any Router, answerClient: GeminiClient? = nil, log: DecisionLog = .shared) {
        self.router = router
        self.log = log
        self.answer = answerClient.map { AnswerSession(client: $0) }
        self.answer?.onFinish = { [weak self] summary in
            self?.answerFinished(summary)
        }
    }

    func submit(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastQuery = trimmed
        Task {
            let result = await router.route(trimmed)
            guard trimmed == lastQuery else { return }   // a newer query won
            apply(result)
        }
    }

    /// The Google results page for the current query, from an answer card's foot.
    func showWebResults() {
        guard !lastQuery.isEmpty else { return }
        show(QueryParser.searchURL(for: lastQuery))
    }

    /// A cited page or a Search Suggestion chip, opened in the web card.
    func open(_ url: URL) {
        show(url)
    }

    private func apply(_ result: RouteResult) {
        lastDecision = result.decision
        switch result.plan {
        case let .web(url):
            answer?.cancel()
            plans = [result.plan]
            _ = page.load(URLRequest(url: url))
            record(result.decision, query: lastQuery)
        case let .answer(format, query):
            guard let answer else {
                // Should not happen: the router only plans answers when a client exists.
                show(QueryParser.searchURL(for: query))
                record(result.decision, query: query)
                return
            }
            plans = [result.plan]
            answer.start(format: format, query: query)
            // Recorded when the answer finishes, with its summary attached.
        }
    }

    private func answerFinished(_ summary: AnswerSummary) {
        guard let answer, answer.query == lastQuery, case .answer = plans.first else { return }
        if let decision = lastDecision {
            record(decision, query: answer.query, answer: summary)
        }
        if case .fellBackToWeb = summary.outcome {
            show(QueryParser.searchURL(for: answer.query))
        }
    }

    private func show(_ url: URL) {
        answer?.cancel()
        plans = [.web(url)]
        _ = page.load(URLRequest(url: url))
    }

    private func record(_ decision: RouteDecision, query: String, answer: AnswerSummary? = nil) {
        let record = DecisionRecord(query: query, decision: decision, answer: answer)
        Task { await log.append(record) }
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
