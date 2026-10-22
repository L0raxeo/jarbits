import Answers
import Foundation
import Images
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

    let page: WebPage
    /// Streams Gemini answers; nil when no Gemini key is configured, in which
    /// case the router never produces an answer plan.
    let answer: AnswerSession?
    /// Loads Wikipedia pictures for image plans.
    let images = ImageSession()
    private(set) var plans: [CardPlan] = []
    private(set) var lastQuery = ""
    private(set) var stage: Stage = .idle
    /// Why the current plan is what it is; logged with the record.
    private(set) var lastDecision: RouteDecision?
    /// What the page pins to its edges, from the watcher that runs inside it.
    private(set) var chrome = PageChrome.plain
    /// A page navigation is in flight, ours or a link tapped inside the
    /// page: the clay shows the wave line meanwhile.
    private(set) var pageLoading = false

    private let router: any Router
    private let log: DecisionLog
    private let chromeHandler: PageChromeHandler
    private var loadTask: Task<Void, Never>?
    private var navigationWatch: Task<Void, Never>?
    private var loadGeneration = 0
    /// Counts navigations, so a stuck one can stop showing as loading.
    private var navigationCount = 0
    /// Counts documents (main-frame commits); a report belongs to the one it
    /// arrived in.
    private var documentGeneration = 0
    /// The current document has finished loading, plus a beat, so reports
    /// apply at once. Before that they wait: resizing the web view during a
    /// page's first layout can crash WebKit's content process.
    private var documentSettled = false
    private var pendingReport: PageChromeReport?
    private var reportedGeneration = -1
    private var previousHost: String?
    /// A page that has not committed by then is shown anyway.
    private let commitTimeout: Duration = .seconds(8)
    /// A navigation that has not finished by then stops showing as loading.
    private let finishTimeout: Duration = .seconds(20)

    init(router: any Router, answerClient: GeminiClient? = nil, log: DecisionLog = .shared) {
        let handler = PageChromeHandler()
        chromeHandler = handler
        page = WebPage(configuration: PageChrome.configuration(handler: handler))
        // Never `page.isInspectable = true`, not even in Debug: an inspectable
        // page under SwiftUI's WebView crashes UIKit's touch delivery on the
        // first tap (iOS 26.5 and 27.0.1, found 2026-10-22). Debug builds
        // print each page's chrome verdict instead; see `apply(_:)`.
        self.router = router
        self.log = log
        self.answer = answerClient.map { AnswerSession(client: $0) }
        self.answer?.onFirstText = { [weak self] in
            self?.answerStarted()
        }
        self.answer?.onFinish = { [weak self] summary in
            self?.answerFinished(summary)
        }
        images.onReady = { [weak self] in
            self?.imageReady()
        }
        images.onFinish = { [weak self] summary in
            self?.imageFinished(summary)
        }
        handler.onReport = { [weak self] report in
            self?.received(report)
        }
        watchNavigations()
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

    /// A page the result links to, such as the Wikipedia article behind an image.
    func open(_ url: URL) {
        load(url)
    }

    /// Back to the idle screen: whatever is in flight stops, the result goes.
    func reset() {
        answer?.cancel()
        images.cancel()
        loadTask?.cancel()
        loadGeneration += 1
        page.stopLoading()
        plans = []
        lastDecision = nil
        chrome = .plain
        pendingReport = nil
        pageLoading = false
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
        case let .image(query):
            answer?.cancel()
            plans = [result.plan]
            stage = .loading
            images.start(query: query)
            // Recorded when the image loads or fails, with its summary attached.
        }
    }

    /// The first picture is decoded: fade the line out, the card in.
    private func imageReady() {
        guard images.query == lastQuery, case .image = plans.first else { return }
        stage = .ready
    }

    private func imageFinished(_ summary: ImageSummary) {
        guard images.query == lastQuery, case .image = plans.first else { return }
        if let decision = lastDecision {
            record(decision, query: images.query, image: summary)
        }
        if case .fellBackToWeb = summary.outcome {
            load(QueryParser.searchURL(for: images.query))
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

    // MARK: The page

    /// Loads `url` into the page and marks the stage ready when the page
    /// commits its first content, fails, or `commitTimeout` passes.
    private func load(_ url: URL) {
        answer?.cancel()
        images.cancel()
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

    /// Every main-frame navigation for the life of the session, ours or a
    /// link tapped in the page: `pageLoading` for the clay, and the document
    /// bookkeeping behind `chrome`. The sequence ends by throwing when a
    /// navigation fails, so it is picked up again.
    private func watchNavigations() {
        navigationWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    for try await event in page.navigations {
                        switch event {
                        case .startedProvisionalNavigation:
                            navigationStarted()
                        case .committed:
                            documentCommitted()
                        case .finished:
                            pageLoading = false
                            documentFinished()
                        case .receivedServerRedirect:
                            break
                        @unknown default:
                            break
                        }
                    }
                } catch {
                    // Offline, bad host, or a load we stopped: not loading any more.
                    pageLoading = false
                }
                // A sequence that ends at once would spin this loop; let the run loop turn.
                await Task.yield()
            }
        }
    }

    private func navigationStarted() {
        pageLoading = true
        navigationCount += 1
        let count = navigationCount
        Task { [weak self, timeout = finishTimeout] in
            try? await Task.sleep(for: timeout)
            guard let self, count == navigationCount else { return }
            // Still the same navigation after all that: the page is usable
            // whatever is still streaming in, so the clay stops waving and
            // whatever the page reported applies.
            pageLoading = false
            await settleDocument()
        }
    }

    /// A new document. A new site starts plain; a page of the same site keeps
    /// its chrome until the new document reports, so a link to a sibling page
    /// never flickers. Same-document navigations (hashes, `pushState`) raise
    /// no event and need none: the watcher in the page follows them.
    private func documentCommitted() {
        documentGeneration += 1
        documentSettled = false
        pendingReport = nil
        let host = page.url?.host()
        if host != previousHost { chrome = .plain }
        previousHost = host
    }

    private func documentFinished() {
        let generation = documentGeneration
        Task { [weak self] in
            // Headers often arrive a beat after the load event.
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, generation == documentGeneration else { return }
            await settleDocument()
        }
    }

    /// From now on reports apply at once, and the one that waited applies.
    /// A document that never reported (not HTML, or its scripts never ran)
    /// gets one direct look, else stays plain.
    private func settleDocument() async {
        guard !documentSettled else { return }
        documentSettled = true
        if let report = pendingReport {
            pendingReport = nil
            apply(report)
        } else if reportedGeneration != documentGeneration {
            let generation = documentGeneration
            let result = try? await page.callJavaScript(PageChrome.probe, contentWorld: PageChrome.world)
            guard generation == documentGeneration else { return }
            if let result, let report = PageChromeReport(result) {
                apply(report)
            } else {
                chrome = .plain
            }
        }
    }

    private func received(_ report: PageChromeReport) {
        reportedGeneration = documentGeneration
        if documentSettled {
            apply(report)
        } else {
            pendingReport = report
        }
    }

    /// Results pages keep the frost at the top whatever they pin there, so
    /// the plain results page stays exactly as it is (it pins nothing at
    /// either edge). Their bottom follows the report: the expanded AI
    /// overview pins its "Ask anything" field there.
    private func apply(_ report: PageChromeReport) {
        var next = report.chrome
        if let url = page.url, QueryParser.isSearchResults(url) {
            next.top = .frost
        }
        #if DEBUG
        // What the watcher decided for this page, in Xcode's console.
        print("page chrome \(page.url?.host() ?? "-"): top \(report.chrome.top) bottom \(report.chrome.bottom) overlay \(report.overlay) atTop \(report.atTop) -> \(next)")
        #endif
        if next != chrome { chrome = next }
    }

    private func record(_ decision: RouteDecision, query: String, answer: AnswerSummary? = nil, image: ImageSummary? = nil) {
        let record = DecisionRecord(query: query, decision: decision, answer: answer, image: image)
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
