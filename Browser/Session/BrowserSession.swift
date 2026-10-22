import Answers
import Foundation
import Observation
import Routing
import WebKit

/// One browsing session: the single web page, the current plan, the router
/// that turns a query into a plan, the answer stream for answer plans, and
/// where the current query is on its way to the screen.
@Observable
@MainActor
final class BrowserSession {
    /// Where the current query is. The home screen shows the wave line from
    /// `routing` through `loading` and fades the result in at `ready`.
    enum Stage: Equatable {
        case idle
        /// Jev asked, no plan yet.
        case routing
        /// Plan known; the page has not committed or no answer text has arrived.
        case loading
        /// The result is on screen.
        case ready
    }

    let page = WebPage()
    /// Streams Gemini answers; nil when no Gemini key is configured, in which
    /// case the router never produces an answer plan.
    let answer: AnswerSession?
    private(set) var plans: [CardPlan] = []
    private(set) var lastQuery = ""
    private(set) var stage: Stage = .idle
    /// Why the current plan is what it is; logged with the record.
    private(set) var lastDecision: RouteDecision?

    private let router: any Router
    private let log: DecisionLog
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    /// A page that has not committed by then is shown anyway.
    private let commitTimeout: Duration = .seconds(8)

    init(router: any Router, answerClient: GeminiClient? = nil, log: DecisionLog = .shared) {
        self.router = router
        self.log = log
        self.answer = answerClient.map { AnswerSession(client: $0) }
        self.answer?.onFirstText = { [weak self] in
            self?.answerStarted()
        }
        self.answer?.onFinish = { [weak self] summary in
            self?.answerFinished(summary)
        }
    }

    func submit(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastQuery = trimmed
        stage = .routing
        Task {
            let result = await router.route(trimmed)
            guard trimmed == lastQuery, stage == .routing else { return }   // a newer query won, or cancelled
            apply(result)
        }
    }

    /// The Google results page for the current query, from under an answer.
    func showWebResults() {
        guard !lastQuery.isEmpty else { return }
        load(QueryParser.searchURL(for: lastQuery))
    }

    /// Back to the idle screen: whatever is in flight stops, the result goes.
    func reset() {
        answer?.cancel()
        loadTask?.cancel()
        loadGeneration += 1
        page.stopLoading()
        plans = []
        lastDecision = nil
        stage = .idle
    }

    private func apply(_ result: RouteResult) {
        lastDecision = result.decision
        switch result.plan {
        case let .web(url):
            answer?.cancel()
            plans = [result.plan]
            load(url)
            record(result.decision, query: lastQuery)
        case let .answer(format, query):
            guard let answer else {
                // Should not happen: the router only plans answers when a client exists.
                plans = [.web(QueryParser.searchURL(for: query))]
                load(QueryParser.searchURL(for: query))
                record(result.decision, query: query)
                return
            }
            plans = [result.plan]
            stage = .loading
            answer.start(format: format, query: query)
            // Recorded when the answer finishes, with its summary attached.
        }
    }

    /// First answer text arrived: fade the line out, the text in.
    private func answerStarted() {
        guard let answer, answer.query == lastQuery, case .answer = plans.first else { return }
        stage = .ready
    }

    private func answerFinished(_ summary: AnswerSummary) {
        guard let answer, answer.query == lastQuery, case .answer = plans.first else { return }
        if let decision = lastDecision {
            record(decision, query: answer.query, answer: summary)
        }
        switch summary.outcome {
        case .fellBackToWeb, .needsLiveData:
            let url = QueryParser.searchURL(for: answer.query)
            plans = [.web(url)]
            load(url)
        case .completed, .partial:
            break
        }
    }

    /// Loads `url` into the page and marks the stage ready when the page
    /// commits its first content, fails, or `commitTimeout` passes.
    private func load(_ url: URL) {
        answer?.cancel()
        plans = [.web(url)]
        stage = .loading
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in page.load(URLRequest(url: url)) {
                    guard generation == loadGeneration else { return }
                    if event == .committed || event == .finished { stage = .ready }
                }
            } catch {
                // Offline, bad host: show whatever WebKit shows rather than wave forever.
                if generation == loadGeneration { stage = .ready }
            }
        }
        Task { [weak self, timeout = commitTimeout] in
            try? await Task.sleep(for: timeout)
            guard let self, generation == loadGeneration, stage == .loading else { return }
            stage = .ready
        }
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
